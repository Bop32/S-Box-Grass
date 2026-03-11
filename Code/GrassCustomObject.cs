using Sandbox;
using Sandbox.Rendering;
using System;
using System.Drawing;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using static Sandbox.VertexLayout;

public struct FrustumPlane
{
	public Vector3 Normal;
	public float Distance;
};

public sealed class GrassCustomObject : SceneCustomObject
{
	struct GrassData
	{
		public Vector3 Position;
		public Vector3 Normal;
		public Color Color;
		public Vector2 Rotation;
		public float Stiffness;
		public float BendAmount;
		public float BladeHash;
		public float DistanceFromCamera;

		public GrassData()
		{
			Position = 0;
			Normal = 0;
			Rotation = 0;
			Color = default;
			Stiffness = 0;
			BendAmount = 0;
			BladeHash = 0;
			DistanceFromCamera = 0;
		}
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
		public Vector2Int Grid;
		public float Size;
		public int Visible;

		public ChunkData()
		{
			Position = 0;
			Size = 0;
			Visible = 0;
			Grid = 0;
		}
	}

	[StructLayout( LayoutKind.Sequential, Pack = 1 )]
	struct SubChunkData
	{
		public Vector2 Position;
		public float Size;
		public int Visible;

		public SubChunkData()
		{
			Position = 0;
			Size = 0;
			Visible = 0;
		}
	};


	private GrassSettings grassSettings;

	private ComputeShader grassComputeShader;

	private ComputeShader chunkComputeShader;

	private ComputeShader subChunkComputeShader;

	private GpuBuffer<GrassData> grassGpuBufferHighLod;
	private GpuBuffer<GrassData> grassGpuBufferLowLod;

	private GpuBuffer<ChunkData> chunkGpuBuffer;
	private GpuBuffer<SubChunkData> subChunkGpuBuffer;

	private int totalGrassCount = 0;

	private CommandList commandList;

	private GrassData[] grassData;

	private GpuBuffer<IndirectCommand> highLodIndirectBuffer;

	private GpuBuffer<IndirectCommand> lowLodIndirectBuffer;

	private CameraComponent camera;

	private const int MAX_GRASS_COUNT = 1_000_000;

	PlayerController playerController;

	public GrassCustomObject( SceneWorld sceneWorld, Grass grass, CameraComponent camera, PlayerController player ) : base( sceneWorld )
	{
		grassSettings = grass.GetSettings();
		this.camera = camera;
		playerController = player;
		commandList = new CommandList();

		//totalGrassCount = MAX_GRASS_COUNT;
		totalGrassCount = grassSettings.GrassCountPerChunk * grassSettings.WorldChunksPerRow;
		grassGpuBufferHighLod = new GpuBuffer<GrassData>( totalGrassCount, GpuBuffer.UsageFlags.Append, "GrassGpuBufferHighLOD" );
		grassGpuBufferLowLod = new GpuBuffer<GrassData>( totalGrassCount, GpuBuffer.UsageFlags.Append, "GrassGpuBufferLowLOD" );

		int chunkGpuBufferCount = grassSettings.WorldChunksPerRow * grassSettings.WorldChunksPerRow;
		chunkGpuBuffer = new GpuBuffer<ChunkData>( chunkGpuBufferCount, GpuBuffer.UsageFlags.Structured, "Test" );
		subChunkGpuBuffer = new GpuBuffer<SubChunkData>( grassSettings.WorldChunksPerRow * grassSettings.WorldChunksPerRow * grassSettings.SubChunksPerRow * grassSettings.SubChunksPerRow, GpuBuffer.UsageFlags.Structured, "SubChunkData" );

		SetupGrassComputeAttributes();
		SetupChunkComputeAttributes();
		//SetupSubChunkComputeAttributes();

		highLodIndirectBuffer = CreateIndirectBuffer( grassSettings.HighLodGrassModel.GetIndexCount( 0 ) );
		lowLodIndirectBuffer = CreateIndirectBuffer( grassSettings.LowLodGrassModel.GetIndexCount( 0 ) );

		Flags.WantsPrePass = false;
		Flags.CastShadows = false;
	}

	private void SetupGrassComputeAttributes()
	{
		grassComputeShader = new ComputeShader( "shaders/Grass.Compute.shader" );

		grassComputeShader.Attributes.Set( "TerrainControlMap", grassSettings.ControlMap );
		grassComputeShader.Attributes.Set( "HeightMap", grassSettings.Terrain.HeightMap );
		grassComputeShader.Attributes.Set( "time", Time.Now );
		grassComputeShader.Attributes.Set( "GrassCount", totalGrassCount );

		grassComputeShader.Attributes.Set( "TerrainPosition", grassSettings.Terrain.WorldPosition );
		grassComputeShader.Attributes.Set( "TerrainSize", new Vector2( grassSettings.Terrain.TerrainSize, grassSettings.Terrain.TerrainHeight ) );

		grassComputeShader.Attributes.Set( "TotalWorldChunks", chunkGpuBuffer.ElementCount );
		grassComputeShader.Attributes.Set( "SubChunkCountPerChunk", grassSettings.SubChunksPerRow * grassSettings.SubChunksPerRow );

		grassComputeShader.Attributes.Set( "ClumpStrength", grassSettings.ClumpStrength );
		grassComputeShader.Attributes.Set( "ClumpSize", grassSettings.ClumpSize );

		grassComputeShader.Attributes.Set( "SubChunkSize", grassSettings.Terrain.TerrainSize / grassSettings.WorldChunksPerRow / grassSettings.SubChunksPerRow );

		grassComputeShader.Attributes.Set( "GrassHighLodData", grassGpuBufferHighLod );
		grassComputeShader.Attributes.Set( "GrassLowLodData", grassGpuBufferLowLod );
	}

	private void SetupChunkComputeAttributes()
	{
		chunkComputeShader = new ComputeShader( "shaders/Chunk.shader" );

		chunkComputeShader.Attributes.Set( "WorldChunksSize", grassSettings.Terrain.TerrainSize / grassSettings.WorldChunksPerRow );
		chunkComputeShader.Attributes.Set( "WorldChunksPerRow", grassSettings.WorldChunksPerRow );
		chunkComputeShader.Attributes.Set( "MaximumUsableChunks", grassSettings.MaxNumberOfUsableChunks );
		chunkComputeShader.Attributes.Set( "TerrainPosition", grassSettings.Terrain.WorldPosition );
		chunkComputeShader.Attributes.Set( "TerrainSize", new Vector2( grassSettings.Terrain.TerrainSize, grassSettings.Terrain.TerrainHeight ) );
		chunkComputeShader.Attributes.Set( "ChunkData", chunkGpuBuffer );
	}

	private void SetupSubChunkComputeAttributes()
	{
		subChunkComputeShader = new ComputeShader( "shaders/SubChunk.Compute.shader" );

		subChunkComputeShader.Attributes.Set( "WorldChunkCount", chunkGpuBuffer.ElementCount );
		subChunkComputeShader.Attributes.Set( "SubChunkData", subChunkGpuBuffer );
		subChunkComputeShader.Attributes.Set( "SubChunkCountPerChunk", grassSettings.SubChunksPerRow );
		subChunkComputeShader.Attributes.Set( "TerrainPosition", grassSettings.Terrain.WorldPosition );
		subChunkComputeShader.Attributes.Set( "TerrainSize", new Vector2( grassSettings.Terrain.TerrainSize, grassSettings.Terrain.TerrainHeight ) );
	}

	public override void RenderSceneObject()
	{
		if ( grassGpuBufferHighLod == null || !grassGpuBufferHighLod.IsValid() ) return;

		commandList.Reset();
		camera.ClearCommandLists();

		FrustumPlane[] cameraFrustum = GetCameraFrustum();

		chunkComputeShader.Attributes.SetData( "FrustumPlanes", cameraFrustum );
		chunkComputeShader.Attributes.Set( "PlayerPosition", playerController.WorldPosition );
		chunkComputeShader.Dispatch( chunkGpuBuffer.ElementCount, 1, 1 );

		grassGpuBufferHighLod.SetCounterValue( 0 );
		grassGpuBufferLowLod.SetCounterValue( 0 );

		grassComputeShader.Attributes.Set( "ChunkData", chunkGpuBuffer );
		grassComputeShader.Attributes.SetData( "FrustumPlanes", cameraFrustum );
		grassComputeShader.Attributes.Set( "CameraPosition", camera.WorldPosition );

		grassComputeShader.Dispatch( totalGrassCount, 1, 1 );

		commandList.Attributes.Set( "CameraPosition", camera.WorldPosition );
		InstanceGrass( grassSettings.HighLodGrassModel, grassGpuBufferHighLod, highLodIndirectBuffer );
		InstanceGrass( grassSettings.LowLodGrassModel, grassGpuBufferLowLod, lowLodIndirectBuffer );

		camera.AddCommandList( commandList, Stage.AfterTransparent, 0 );

		RenderDebugText();

	}

	private void RenderChunksFromCamera()
	{

	}

	private void RenderDebugText()
	{
		if ( !highLodIndirectBuffer.IsValid() ) return;
		int[] arr = new int[4];


		highLodIndirectBuffer.GetData( arr, 0, arr.Length );

		Gizmo.Draw.ScreenText( $"Number of high Lod grass: `{arr[1]}`", new Vector2( 10, 0 ), "Arial", 20 );

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

	private GpuBuffer<IndirectCommand> CreateIndirectBuffer( int indexCount )
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

		grassGpuBufferLowLod?.Dispose();
		grassGpuBufferLowLod = null;

		lowLodIndirectBuffer?.Dispose();
		lowLodIndirectBuffer = null;

		chunkGpuBuffer?.Dispose();
		chunkGpuBuffer = null;

		subChunkGpuBuffer?.Dispose();
		subChunkGpuBuffer = null;
	}
}
