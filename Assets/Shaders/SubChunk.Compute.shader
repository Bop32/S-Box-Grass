MODES
{
    Default();
}

CS
{
    // clang-format off
   #include "system.fxc"

	struct SubChunkData
	{
		float2 Position;
		float Size;
		int Visible;
	};

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

	cbuffer FrustumPlanes
	{
		FrustumPlane planes[6];
	};

	RWStructuredBuffer<ChunkData> chunkBuffer <Attribute("ChunkData"); >;
	RWStructuredBuffer<SubChunkData> subChunkBuffer <Attribute("SubChunkData"); >;

	int worldChunkCount <Attribute("WorldChunkCount"); >;

	float3 terrainPosition < Attribute("TerrainPosition"); >;

	float2 terrainSize <Attribute("TerrainSize"); >;

	int subChunkPerRow <Attribute("SubChunkCountPerChunk"); >;

    // clang-format on

    bool AABBInsideFrustum(float3 min, float3 max)
    {
        for (int i = 0; i < 6; i++)
        {
            float3 normal = planes[i].Normal;

            float3 positive = float3(normal.x >= 0 ? max.x : min.x, normal.y >= 0 ? max.y : min.y, normal.z >= 0 ? max.z : min.z);

            if (dot(normal, positive) - planes[i].Distance < 0)
                return false;
        }

        return true;
    }

    float2 GetSubChunkOffset(uint currentChunkIndex, float subChunkSize)
    {
        uint chunkIndexX = currentChunkIndex % subChunkPerRow;
        uint chunkIndexY = currentChunkIndex / subChunkPerRow;

        return float2(chunkIndexX * subChunkSize, chunkIndexY * subChunkSize);
    }

    [numthreads(8, 1, 1)]
    void MainCs(uint3 id: SV_DispatchThreadID)
    {
        uint index = id.x;

        uint subChunksPerChunk = subChunkPerRow * subChunkPerRow;

        uint worldChunkIndex = index / subChunksPerChunk;

        ChunkData chunkData = chunkBuffer[worldChunkIndex];

        if (!chunkData.Visible)
        {
            SubChunkData emptySubChunk;
            emptySubChunk.Visible = false;
            subChunkBuffer[index] = emptySubChunk;
            return;
        }

        float subChunkSize = chunkData.Size / subChunkPerRow;

        float chunkHalf = chunkData.Size * 0.5f;

        float2 chunkMin = chunkData.Position - chunkHalf;
        uint localSubChunkIndex = index % subChunksPerChunk;

        float2 position = chunkMin + GetSubChunkOffset(localSubChunkIndex, subChunkSize);

        float2 minXY = position - subChunkSize;
        float2 maxXY = position + subChunkSize;

        float minZ = terrainPosition.z;
        float maxZ = terrainPosition.z + terrainSize.y;

        float3 mins = float3(minXY, minZ);
        float3 max = float3(maxXY, maxZ);

        SubChunkData subChunkDataTmp;

        subChunkDataTmp.Position = position;
        subChunkDataTmp.Size = subChunkSize;
        subChunkDataTmp.Visible = AABBInsideFrustum(mins, max);
        subChunkBuffer[index] = subChunkDataTmp;
    }
}
