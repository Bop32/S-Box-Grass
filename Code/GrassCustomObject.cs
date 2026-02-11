using Sandbox;
using Sandbox.Rendering;
using System;
using System.Runtime.InteropServices;

public sealed class GrassCustomObject : SceneCustomObject
{
	struct GrassData
	{
		Vector3 Position;
		Vector3 Normal;
		float Rotation;
		float Stiffness;
		float BendAmount;
		float BladeHash;
		float DistanceFromCamera;

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

	private Model highLodGrassModel = null;

	private Model lowLodGrassModel = null;

	private Terrain terrain = null;

	private int grassCountPerChunk = 0;

	private int chunkCount = 0;

	public Vector2 chunkSize = Vector2.Zero;

	private float clumpStrength;

	private float clumpSize;

	private ComputeShader grassComputeShader;
	private GpuBuffer<GrassData> grassGpuBufferHighLod;

	private GpuBuffer<GrassData> grassGpuBufferLowLod;

	private int totalGrassCount = 0;

	private CommandList commandList;

	private GrassData[] grassData;

	private GpuBuffer<IndirectCommand> highLodIndirectBuffer;

	private GpuBuffer<IndirectCommand> lowLodIndirectBuffer;

	private CameraComponent camera;

	private const int MAX_GRASS_COUNT = 1_000_000;

	public GrassCustomObject( SceneWorld sceneWorld, Grass grass, CameraComponent camera ) : base( sceneWorld )
	{
		SetupGrassSettings( grass, camera );

		commandList = new CommandList();

		//totalGrassCount = MAX_GRASS_COUNT;
		totalGrassCount = grassCountPerChunk * chunkCount ;
		grassGpuBufferHighLod = new GpuBuffer<GrassData>( totalGrassCount, GpuBuffer.UsageFlags.Append, "GrassGpuBufferHighLOD" );
		grassGpuBufferLowLod = new GpuBuffer<GrassData>( totalGrassCount, GpuBuffer.UsageFlags.Append, "GrassGpuBufferLowLOD" );

		grassComputeShader = new ComputeShader( "shaders/Grass.Compute.shader" );

		grassComputeShader.Attributes.Set( "HeightMap", terrain.HeightMap );
		grassComputeShader.Attributes.Set( "time", Time.Now );
		grassComputeShader.Attributes.Set( "GrassCount", totalGrassCount );
		grassComputeShader.Attributes.Set( "TerrainPosition", terrain.WorldPosition );
		grassComputeShader.Attributes.Set( "TerrainSize", new Vector2( terrain.TerrainSize, terrain.TerrainHeight ) );
		grassComputeShader.Attributes.Set( "ChunkSize", chunkSize );
		grassComputeShader.Attributes.Set( "ChunkCount", chunkCount );
		grassComputeShader.Attributes.Set( "ClumpStrength", clumpStrength );
		grassComputeShader.Attributes.Set( "ClumpSize", clumpSize );
		grassComputeShader.Attributes.Set( "GrassHighLodData", grassGpuBufferHighLod );
		grassComputeShader.Attributes.Set( "GrassLowLodData", grassGpuBufferLowLod );

		grassData = new GrassData[totalGrassCount];
		grassGpuBufferHighLod.SetData( grassData );

		highLodIndirectBuffer = CreateIndirectBuffer( highLodGrassModel.GetIndexCount( 0 ) );
		lowLodIndirectBuffer = CreateIndirectBuffer( lowLodGrassModel.GetIndexCount( 0 ) );

		Flags.WantsPrePass = true;
		Flags.CastShadows = true;
	}

	private void SetupGrassSettings( Grass grass, CameraComponent camera )
	{
		GrassSettings grassSettings = grass.GetSettings();

		highLodGrassModel = grassSettings.HighLodGrassModel;
		lowLodGrassModel = grassSettings.LowLodGrassModel;
		terrain = grassSettings.Terrain;
		grassCountPerChunk = grassSettings.GrassCountPerChunk;
		chunkCount = grassSettings.ChunkCount;
		chunkSize = grassSettings.ChunkSize;
		clumpStrength = grassSettings.ClumpStrength;
		clumpSize = grassSettings.ClumpSize;
		this.camera = camera;
	}

	public override void RenderSceneObject()
	{
		if ( grassGpuBufferHighLod == null || !grassGpuBufferHighLod.IsValid() ) return;

		commandList.Reset();
		camera.ClearCommandLists();

		grassGpuBufferHighLod.SetCounterValue( 0 );
		grassGpuBufferLowLod.SetCounterValue( 0 );

		grassComputeShader.Attributes.SetData( "FrustumPlanes", GetCameraFrustum() );
		grassComputeShader.Attributes.Set( "CameraPosition", camera.WorldPosition );

		grassComputeShader.Dispatch( totalGrassCount, 1, 1 );

		commandList.Attributes.Set( "CameraPosition", camera.WorldPosition );
		InstanceGrass( highLodGrassModel, grassGpuBufferHighLod, highLodIndirectBuffer );
		InstanceGrass( lowLodGrassModel, grassGpuBufferLowLod, lowLodIndirectBuffer );

		camera.AddCommandList( commandList, Stage.AfterTransparent, 0 );

		RenderGrassCount();

		//DebugOverlaySystem.Current.Texture( terrain.HeightMap, new Rect( 0, 0, 128, 128 ) );
	}

	private void RenderGrassCount()
	{
		int[] arr = new int[2];
		highLodIndirectBuffer.GetData( arr, 0, arr.Length );

		Gizmo.Draw.ScreenText( $"Number of high Lod grass: `{arr[1]}`", new Vector2(10, 0), "Arial", 20);

		lowLodIndirectBuffer.GetData( arr, 0, arr.Length );

		Gizmo.Draw.ScreenText( $"Number of low Lod grass: `{arr[1]}`", new Vector2( 10, 20 ), "Arial", 20 );

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

	private GpuBuffer<IndirectCommand> CreateIndirectBuffer( int indexCount)
	{
		GpuBuffer<IndirectCommand> gpuBuffer = new( 1, GpuBuffer.UsageFlags.IndirectDrawArguments | GpuBuffer.UsageFlags.Structured, "IndirectBuffer" );

		gpuBuffer.SetData( [
				new IndirectCommand
			{
				IndexCount = (uint)highLodGrassModel.GetIndexCount(0),
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
