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

	RWStructuredBuffer<ChunkData> chunkData <Attribute("ChunkData"); >;

	float2 terrainSize <Attribute("TerrainSize"); >;

	float3 terrainPosition < Attribute("TerrainPosition"); >;


	float2 GetWorldChunkOffset(uint currentChunkIndex)
	{
		uint chunkIndexX = currentChunkIndex % worldChunkPerRow;
		uint chunkIndexY = currentChunkIndex / worldChunkPerRow;
		
		return float2(chunkIndexX * worldChunkSize, chunkIndexY * worldChunkSize) + (worldChunkSize * 0.5f);
	}

	bool AABBInsideFrustum(float3 min, float3 max)
	{
		for (int i = 0; i < 6; i++)
		{
			float3 normal = planes[i].Normal;

			float3 positive = float3(normal.x >= 0 ? max.x : min.x, normal.y >= 0 ? max.y : min.y, normal.z >= 0 ? max.z : min.z);

			if (dot(normal, positive) - planes[i].Distance < 0) return false;
		}

		return true;
	}


	[numthreads( 8, 1, 1 )]
	void MainCs( uint3 id : SV_DispatchThreadID )
	{
		uint index = id.x;

		float2 position = terrainPosition.xy + GetWorldChunkOffset(index);

		float minZ = terrainPosition.z;
		float maxZ = terrainPosition.z + terrainSize.y;

		float2 halfChunk = worldChunkSize * 0.5f;

		float2 minXY = position - halfChunk;
		float2 maxXY = position + halfChunk;

		float3 min = float3(minXY, minZ); 
		float3 max = float3(maxXY, maxZ); 

		ChunkData chunkDataTmp;
		
		chunkDataTmp.Position = position;
		chunkDataTmp.Free = index > maximumNumberOfUsableChunks;
		chunkDataTmp.Size = worldChunkSize;
		chunkDataTmp.Visible = true;//AABBInsideFrustum(min, max);
		chunkData[index] = chunkDataTmp;
	}
}