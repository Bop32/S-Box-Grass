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
		float BendAmount;
		float Noise;
		bool ShouldDiscard;
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
	private Model grassModel;

	[Property]
	private Terrain terrain;

	[Property]
	public int grassCountPerChunk;

	[Property]
	public int chunkCount;

	[Property]
	public Vector2 chunkSize;

	private ComputeShader grassComputeShader;
	private GpuBuffer<GrassData> grassGpuBuffer;

	private int totalGrassCount = 0;

	private CommandList commandList;

	private GrassData[] grassData;

	private GpuBuffer<IndirectCommand> indirectBuffer;

	protected override void OnAwake()
	{
		commandList = new CommandList();

		totalGrassCount = grassCountPerChunk * chunkCount;
		grassGpuBuffer = new GpuBuffer<GrassData>( totalGrassCount, GpuBuffer.UsageFlags.Append, "GrassGpuBuffer" );

		grassComputeShader = new ComputeShader( "shaders/Grass.Compute.shader" );

		grassComputeShader.Attributes.Set( "HeightMap", terrain.HeightMap );
		grassComputeShader.Attributes.Set( "time", Time.Now );
		grassComputeShader.Attributes.Set( "GrassCount", totalGrassCount );
		grassComputeShader.Attributes.Set( "TerrainPosition", terrain.WorldPosition );
		grassComputeShader.Attributes.Set( "ChunkSize", chunkSize );
		grassComputeShader.Attributes.Set( "ChunkCount", chunkCount );
		grassComputeShader.Attributes.Set( "GrassData", grassGpuBuffer );

		grassData = new GrassData[totalGrassCount];
		grassGpuBuffer.SetData( grassData );

		indirectBuffer = new( 1, GpuBuffer.UsageFlags.IndirectDrawArguments | GpuBuffer.UsageFlags.Structured, "IndirectBuffer" );

		indirectBuffer.SetData( [
				new IndirectCommand {
				IndexCount = (uint)grassModel.GetIndexCount(0),
				InstanceCount = (uint)totalGrassCount,
				FirstIndex = 0,
				VertexOffset = 0,
				FirstInstance = 0
			}
			] );
	}

	public override void Render()
	{
		if ( grassGpuBuffer == null || !grassGpuBuffer.IsValid() ) return;

		commandList.Reset();


		grassGpuBuffer.SetCounterValue( 0 );
		grassComputeShader.Attributes.SetData( "FrustumPlanes", GetCameraFrustum() );
		grassComputeShader.Dispatch( totalGrassCount, 1, 1 );

		commandList.Attributes.Set( "GrassData", grassGpuBuffer );

		grassGpuBuffer.CopyStructureCount( indirectBuffer, 4 );
		commandList.DrawModelInstancedIndirect( grassModel, indirectBuffer );

		InsertCommandList( commandList, Stage.AfterOpaque, 0, "Grass" );
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

	protected override void OnDestroy()
	{
		grassGpuBuffer?.Dispose();
		grassGpuBuffer = null;

		indirectBuffer?.Dispose();
		indirectBuffer = null;
	}
}
