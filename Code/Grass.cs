using Sandbox;
using Sandbox.Rendering;
using System.Runtime.InteropServices;

public sealed class Grass : BasePostProcess<Grass>
{
	struct GrassData
	{
		Vector3 Position;
		Vector3 Normal;
		float Rotation;
		float Stiffness;
		float BendAmount;
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

	[Property]
	private Model highLodGrassModel;

	[Property]
	private Mesh test;

	[Property]
	private Model lowLodGrassModel;

	[Property]
	private Terrain terrain;

	[Property]
	public int grassCountPerChunk;

	[Property]
	public int chunkCount;

	[Property]
	public Vector2 chunkSize;

	private ComputeShader grassComputeShader;
	private GpuBuffer<GrassData> grassGpuBufferHighLod;

	private GpuBuffer<GrassData> grassGpuBufferLowLod;

	private int totalGrassCount = 0;

	private CommandList commandList;

	private GrassData[] grassData;

	private GpuBuffer<IndirectCommand> highLodIndirectBuffer;

	private GpuBuffer<IndirectCommand> lowLodIndirectBuffer;

	protected override void OnAwake()
	{
		commandList = new CommandList();

		totalGrassCount = grassCountPerChunk * chunkCount;
		grassGpuBufferHighLod = new GpuBuffer<GrassData>( totalGrassCount, GpuBuffer.UsageFlags.Append, "GrassGpuBufferHighLOD" );
		grassGpuBufferLowLod = new GpuBuffer<GrassData>( totalGrassCount, GpuBuffer.UsageFlags.Append, "GrassGpuBufferLowLOD" );

		grassComputeShader = new ComputeShader( "shaders/Grass.Compute.shader" );

		grassComputeShader.Attributes.Set( "HeightMap", terrain.HeightMap );
		grassComputeShader.Attributes.Set( "time", Time.Now );
		grassComputeShader.Attributes.Set( "GrassCount", totalGrassCount );
		grassComputeShader.Attributes.Set( "TerrainPosition", terrain.WorldPosition );
		grassComputeShader.Attributes.Set( "ChunkSize", chunkSize );
		grassComputeShader.Attributes.Set( "ChunkCount", chunkCount );
		grassComputeShader.Attributes.Set( "GrassHighLodData", grassGpuBufferHighLod );
		grassComputeShader.Attributes.Set( "GrassLowLodData", grassGpuBufferLowLod );

		grassData = new GrassData[totalGrassCount];
		grassGpuBufferHighLod.SetData( grassData );

		highLodIndirectBuffer = CreateIndirectBuffer( highLodGrassModel.GetIndexCount( 0 ), totalGrassCount );
		lowLodIndirectBuffer = CreateIndirectBuffer( lowLodGrassModel.GetIndexCount( 0 ), totalGrassCount );


	}

	public override void Render()
	{
		if ( grassGpuBufferHighLod == null || !grassGpuBufferHighLod.IsValid() ) return;

		commandList.Reset();


		grassGpuBufferHighLod.SetCounterValue( 0 );
		grassGpuBufferLowLod.SetCounterValue( 0 );

		grassComputeShader.Attributes.SetData( "FrustumPlanes", GetCameraFrustum() );
		grassComputeShader.Attributes.Set( "CameraPosition", Camera.WorldPosition );

		grassComputeShader.Dispatch( totalGrassCount, 1, 1 );

		commandList.Attributes.Set( "CameraPosition", Camera.WorldPosition );
		InstanceGrass( highLodGrassModel, grassGpuBufferHighLod, highLodIndirectBuffer );
		InstanceGrass( lowLodGrassModel, grassGpuBufferLowLod, lowLodIndirectBuffer );

		InsertCommandList( commandList, Stage.AfterOpaque, 0, "Grass" );
	}

	private void InstanceGrass( Model grassModel, GpuBuffer<GrassData> gpuBuffer, GpuBuffer<IndirectCommand> indirectCommandBuffer )
	{
		commandList.Attributes.Set( "GrassData", gpuBuffer );

		gpuBuffer.CopyStructureCount( indirectCommandBuffer, 4 );
		commandList.DrawModelInstancedIndirect( grassModel, indirectCommandBuffer );
	}

	private FrustumPlane[] GetCameraFrustum()
	{
		Frustum frustum = Camera.GetFrustum();

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

	private GpuBuffer<IndirectCommand> CreateIndirectBuffer( int indexCount, int instanceCount )
	{
		GpuBuffer<IndirectCommand> gpuBuffer = new( 1, GpuBuffer.UsageFlags.IndirectDrawArguments | GpuBuffer.UsageFlags.Structured, "IndirectBuffer" );

		gpuBuffer.SetData( [
				new IndirectCommand
			{
				IndexCount = (uint)highLodGrassModel.GetIndexCount(0),
				InstanceCount = (uint)totalGrassCount,
				FirstIndex = 0,
				VertexOffset = 0,
				FirstInstance = 0
			}] );

		return gpuBuffer;
	}

	protected override void OnDestroy()
	{
		grassGpuBufferHighLod?.Dispose();
		grassGpuBufferHighLod = null;

		highLodIndirectBuffer?.Dispose();
		highLodIndirectBuffer = null;
	}

	protected override void OnDisabled()
	{
		grassGpuBufferHighLod?.Dispose();
		grassGpuBufferHighLod = null;

		highLodIndirectBuffer?.Dispose();
		highLodIndirectBuffer = null;
	}
}
