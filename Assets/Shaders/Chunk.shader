MODES
{
    Default();
}

CS
{
	#include "system.fxc"

	struct ChunkData
	{
		float2 Position;
		float Size;
		int ChunkIndex;
		int Visible;
		int Free;
	};

	struct FrustumPlane
	{
		float3 Normal;
		float Distance;
	};

	cbuffer	FrustumPlanes
	{
		FrustumPlane planes[6];
	};

	float worldChunkSize < Attribute("WorldChunksSize"); >;
	int worldChunkPerRow < Attribute("WorldChunksPerRow"); >;

	int maximumNumberOfUsableChunks <Attribute("MaximumUsableChunks"); >;

	int grassCount <Attribute("GrassCount"); >;

	RWStructuredBuffer<ChunkData> chunkData <Attribute("ChunkData"); >;

	float2 GetWorldChunkOffset(uint index, uint grassPerChunk, uint currentChunkIndex, float2 halfChunk)
	{
		uint chunkIndexX = currentChunkIndex % worldChunkPerRow;
		uint chunkIndexY = currentChunkIndex / worldChunkPerRow;
		
		return float2(chunkIndexX * worldChunkSize, chunkIndexY * worldChunkSize) + halfChunk;
	}

	bool InsideCameraFrustrum(float3 center)
	{
		for (int i = 0; i < 6; i++)
		{
			if(dot(planes[i].Normal, center) - planes[i].Distance < 0) return false;
		}
		
		return true;
	}

	[numthreads( 8, 1, 1 )]
	void MainCs( uint3 id : SV_DispatchThreadID )
	{
		uint index = id.x;

		uint grassPerChunk = grassCount / worldChunkPerRow; 

		ChunkData chunkDataTmp;

		chunkDataTmp.Position = GetWorldChunkOffset(index, grassPerChunk, index, worldChunkSize * 0.5);
		chunkDataTmp.ChunkIndex = index;
		chunkDataTmp.Free = index > maximumNumberOfUsableChunks;
		chunkDataTmp.Size = worldChunkSize;
		chunkDataTmp.Visible = true;
		chunkData[index] = chunkDataTmp;
	}	
}