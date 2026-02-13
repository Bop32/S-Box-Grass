MODES
{
    Default();
}

CS
{
	#include "system.fxc"

	struct SubChunkData
	{
		float2 Min;
		float2 Max;

		int ParentChunkIndex;
		int Visible;
	};

	struct ChunkData
	{
		float2 Position;
		float Size;
		int ChunkIndex;
		int Visible;
		int Free;
	};

	RWStructuredBuffer<SubChunkData> subChunkData <Attribute("SubChunkData"); >;
	RWStructuredBuffer<ChunkData> chunkData <Attribute("ChunkData"); >;

	int worldChunkCount <Attribute("WorldChunkCount"); >;

	[numthreads( 8, 1, 1 )]
	void MainCs( uint3 id : SV_DispatchThreadID )
	{
		uint index = id.x;

		int worldChunkIndex = index / worldChunkCount;

		ChunkData chunkDataTmp = chunkData[worldChunkIndex];
		
		float halfSize = chunkDataTmp.Size * 0.5;

		float2 min = chunkDataTmp.Position - halfSize;
		float2 max = chunkDataTmp.Position + halfSize;

		SubChunkData subChunkDataTmp;

		subChunkDataTmp.ParentChunkIndex = worldChunkIndex;
		subChunkDataTmp.Min = min;
		subChunkDataTmp.Max = max;

	}	
}