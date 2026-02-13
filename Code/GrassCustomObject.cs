using Sandbox;
using Sandbox.Rendering;
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using static Sandbox.VertexLayout;

public sealed class GrassCustomObject : SceneCustomObject
{
	struct GrassData
	{
		public Vector3 Position;
		public Vector3 Normal;
		public float Rotation;
		public float Stiffness;
		public float BendAmount;
		public float BladeHash;
		public float DistanceFromCamera;

		public GrassData()
		{
			Position = 0;
			Normal = 0;
			Rotation = 0;
			Stiffness = 0;
			BendAmount = 0;
			BladeHash = 0;
			DistanceFromCamera = 0;
		}
	};

	struct FrustumPlane
	{
		public Vector3 Normal;
		public float Distance;
	};

	public struct IndirectCommand
	{
		public uint IndexCount;      // Number of indices in the mesh
		public uint InstanceCount;   // GPU will increment this
		public uint FirstIndex;
		public int VertexOffset;
		public uint FirstInstance;
	}

	struct ChunkData
	{
		public Vector2 Position;
		public float Size;
		public int CurrentChunk;
		public int Visible;
		public int Free;

		public ChunkData()
		{
			Position = 0;
			Size = 0;
			CurrentChunk = 0;
			Visible = 0;
			Free = 0;
		}
	}


	private Grass grassSettings;

	private ComputeShader grassComputeShader;

	private ComputeShader chunkComputeShader;

	private GpuBuffer<GrassData> grassGpuBufferHighLod;
	private GpuBuffer<GrassData> grassGpuBufferLowLod;

	private GpuBuffer<ChunkData> chunkGpuBuffer;

	private int totalGrassCount = 0;

	private CommandList commandList;

	private GrassData[] grassData;

	private GpuBuffer<IndirectCommand> highLodIndirectBuffer;

	private GpuBuffer<IndirectCommand> lowLodIndirectBuffer;

	private CameraComponent camera;

	private const int MAX_GRASS_COUNT = 1_000_000;

	public GrassCustomObject( SceneWorld sceneWorld, Grass grass, CameraComponent camera ) : base( sceneWorld )
	{
		grassSettings = grass;
		this.camera = camera;

		commandList = new CommandList();

		//totalGrassCount = MAX_GRASS_COUNT;
		totalGrassCount = grassSettings.GrassCountPerChunk * grassSettings.WorldChunksPerRow;
		grassGpuBufferHighLod = new GpuBuffer<GrassData>( totalGrassCount, GpuBuffer.UsageFlags.Append, "GrassGpuBufferHighLOD" );
		grassGpuBufferLowLod = new GpuBuffer<GrassData>( totalGrassCount, GpuBuffer.UsageFlags.Append, "GrassGpuBufferLowLOD" );

		chunkGpuBuffer = new GpuBuffer<ChunkData>( grassSettings.WorldChunksPerRow * grassSettings.WorldChunksPerRow, GpuBuffer.UsageFlags.Structured, "ChunkData" );

		SetupGrassComputeAttributes();
		SetupChunkComputeAttributes();

		grassData = new GrassData[totalGrassCount];
		grassGpuBufferHighLod.SetData( grassData );

		highLodIndirectBuffer = CreateIndirectBuffer( grassSettings.HighLodGrassModel.GetIndexCount( 0 ) );
		lowLodIndirectBuffer = CreateIndirectBuffer( grassSettings.LowLodGrassModel.GetIndexCount( 0 ) );

		Flags.WantsPrePass = true;
		Flags.CastShadows = true;
	}

	private void SetupGrassComputeAttributes()
	{
		grassComputeShader = new ComputeShader( "shaders/Grass.Compute.shader" );

		grassComputeShader.Attributes.Set( "HeightMap", grassSettings.Terrain.HeightMap );
		grassComputeShader.Attributes.Set( "time", Time.Now );
		grassComputeShader.Attributes.Set( "GrassCount", totalGrassCount );

		grassComputeShader.Attributes.Set( "TerrainPosition", grassSettings.Terrain.WorldPosition );
		grassComputeShader.Attributes.Set( "TerrainSize", new Vector2( grassSettings.Terrain.TerrainSize, grassSettings.Terrain.TerrainHeight ) );

		grassComputeShader.Attributes.Set( "GrassPerChunk",  grassSettings.GrassCountPerChunk / grassSettings.WorldChunksPerRow);

		grassComputeShader.Attributes.Set( "SubChunksSize", grassSettings.Terrain.TerrainSize / grassSettings.WorldChunksPerRow / grassSettings.SubChunksPerRow );
		grassComputeShader.Attributes.Set( "SubChunksPerRow", grassSettings.SubChunksPerRow );

		grassComputeShader.Attributes.Set( "ClumpStrength", grassSettings.ClumpStrength );
		grassComputeShader.Attributes.Set( "ClumpSize", grassSettings.ClumpSize );

		grassComputeShader.Attributes.Set( "GrassHighLodData", grassGpuBufferHighLod );
		grassComputeShader.Attributes.Set( "GrassLowLodData", grassGpuBufferLowLod );
	}

	private void SetupChunkComputeAttributes()
	{
		chunkComputeShader = new ComputeShader( "shaders/Chunk.shader" );

		chunkComputeShader.Attributes.Set( "WorldChunksSize", grassSettings.Terrain.TerrainSize / grassSettings.WorldChunksPerRow );
		chunkComputeShader.Attributes.Set( "WorldChunksPerRow", grassSettings.WorldChunksPerRow );
		chunkComputeShader.Attributes.Set( "GrassCount", totalGrassCount );
		chunkComputeShader.Attributes.Set( "MaximumUsableChunks", grassSettings.MaxNumberOfUsableChunks );
		chunkComputeShader.Attributes.Set( "ChunkData", chunkGpuBuffer );
	}

	public override void RenderSceneObject()
	{
		if ( grassGpuBufferHighLod == null || !grassGpuBufferHighLod.IsValid() ) return;

		commandList.Reset();
		camera.ClearCommandLists();

		chunkComputeShader.Attributes.SetData( "FrustumPlanes", GetCameraFrustum() );

		chunkComputeShader.Dispatch(grassSettings.WorldChunksPerRow, 1, 1);

		grassGpuBufferHighLod.SetCounterValue( 0 );
		grassGpuBufferLowLod.SetCounterValue( 0 );

		grassComputeShader.Attributes.Set( "ChunkData", chunkGpuBuffer );
		grassComputeShader.Attributes.SetData( "FrustumPlanes", GetCameraFrustum() );
		grassComputeShader.Attributes.Set( "CameraPosition", camera.WorldPosition );

		grassComputeShader.Dispatch( totalGrassCount, 1, 1 );

		commandList.Attributes.Set( "CameraPosition", camera.WorldPosition );
		InstanceGrass( grassSettings.HighLodGrassModel, grassGpuBufferHighLod, highLodIndirectBuffer );
		InstanceGrass( grassSettings.LowLodGrassModel, grassGpuBufferLowLod, lowLodIndirectBuffer );

		camera.AddCommandList( commandList, Stage.AfterTransparent, 0 );

		//RenderDebugText();

		//DebugOverlaySystem.Current.Texture( terrain.HeightMap, new Rect( 0, 0, 128, 128 ) );
	}

	private void RenderDebugText()
	{
		int[] arr = new int[4];
		highLodIndirectBuffer.GetData( arr, 0, arr.Length );

		Gizmo.Draw.ScreenText( $"Number of high Lod grass: `{arr[1]}`", new Vector2(10, 0), "Arial", 20);

		lowLodIndirectBuffer.GetData( arr, 0, arr.Length );

		Gizmo.Draw.ScreenText( $"Number of low Lod grass: `{arr[1]}`", new Vector2( 10, 20 ), "Arial", 20 );

		Gizmo.Draw.ScreenText( $"Total grass count: `{totalGrassCount}`", new Vector2( 10, 40 ), "Arial", 20 );
	}

	private void InstanceGrass( Model grassModel, GpuBuffer<GrassData> gpuBuffer, GpuBuffer<IndirectCommand> indirectCommandBuffer )
	{
		commandList.Attributes.Set( "GrassData", gpuBuffer );

		gpuBuffer.CopyStructureCount( indirectCommandBuffer, 4 );
		commandList.DrawModelInstancedIndirect( grassModel, indirectCommandBuffer );
	}

	private FrustumPlane[] GetCameraFrustum()
	{
		Frustum frustum = camera.GetFrustum();

		FrustumPlane[] planes = new FrustumPlane[6];

		const float shrinkAmount = 50.0f;

		planes[0] = new FrustumPlane { Normal = frustum.RightPlane.Normal, Distance = frustum.RightPlane.Distance - shrinkAmount };
		planes[1] = new FrustumPlane { Normal = frustum.LeftPlane.Normal, Distance = frustum.LeftPlane.Distance - shrinkAmount };
		planes[2] = new FrustumPlane { Normal = frustum.TopPlane.Normal, Distance = frustum.TopPlane.Distance - shrinkAmount };
		planes[3] = new FrustumPlane { Normal = frustum.BottomPlane.Normal, Distance = frustum.BottomPlane.Distance - shrinkAmount };
		planes[4] = new FrustumPlane { Normal = frustum.NearPlane.Normal, Distance = frustum.NearPlane.Distance - shrinkAmount };
		planes[5] = new FrustumPlane { Normal = frustum.FarPlane.Normal, Distance = frustum.FarPlane.Distance - shrinkAmount };

		return planes;
	}

	private GpuBuffer<IndirectCommand> CreateIndirectBuffer(int indexCount)
	{
		GpuBuffer<IndirectCommand> gpuBuffer = new( 1, GpuBuffer.UsageFlags.IndirectDrawArguments | GpuBuffer.UsageFlags.Structured, "IndirectBuffer" );

		gpuBuffer.SetData( [
				new IndirectCommand
			{
				IndexCount = (uint)indexCount,
				InstanceCount = 0,
				FirstIndex = 0,
				VertexOffset = 0,
				FirstInstance = 0
			}] );

		return gpuBuffer;
	}

	public void DestroyBuffers()
	{
		grassGpuBufferHighLod?.Dispose();
		grassGpuBufferHighLod = null;

		highLodIndirectBuffer?.Dispose();
		highLodIndirectBuffer = null;
	}
}
