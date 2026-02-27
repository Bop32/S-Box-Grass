MODES
{
    Default();
}

CS
{
    // clang-format off
   #include "system.fxc"
   #include "common/shared.hlsl"

    // clang-format on
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

    // clang-format off
	float worldChunkSize < Attribute("WorldChunksSize"); >;

	int worldChunkPerRow < Attribute("WorldChunksPerRow"); >;

	int maximumNumberOfUsableChunks <Attribute("MaximumUsableChunks"); >;

	RWStructuredBuffer<ChunkData> chunkData <Attribute("ChunkData"); >;

	float2 terrainSize <Attribute("TerrainSize"); >;

	float3 terrainPosition < Attribute("TerrainPosition"); >;
	float3 cameraPosition < Attribute("CameraPosition"); >;

    // clang-format on

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

            if (dot(normal, positive) - planes[i].Distance < 0)
                return false;
        }

        return true;
    }

    [numthreads(8, 1, 1)]
    void MainCs(uint3 id: SV_DispatchThreadID)
    {
        uint index = id.x;

        uint gridSize = worldChunkPerRow;

        int totalChunks = gridSize * gridSize;

        if (index >= totalChunks)
            return;

        float chunkSize = 700;

        int halfGrid = gridSize * 0.5f;

        int x = (index % gridSize) - halfGrid;
        int y = (index / gridSize) - halfGrid;

        float halfChunkSize = chunkSize * 0.5f;

        float baseX = floor(cameraPosition.x / chunkSize) * chunkSize + halfChunkSize;
        float baseY = floor(cameraPosition.y / chunkSize) * chunkSize + halfChunkSize;

        float worldX = baseX + x * chunkSize + halfChunkSize;
        float worldY = baseY + y * chunkSize + halfChunkSize;

        float2 chunkPosition = float2(worldX, worldY);

        float3 min = float3(worldX - chunkSize * 0.5, worldY - chunkSize * 0.5, terrainPosition.z);
        float3 max = float3(worldX + chunkSize * 0.5, worldY + chunkSize * 0.5, terrainPosition.z + terrainSize.y);

        ChunkData chunkDataTmp;

        chunkDataTmp.Position = chunkPosition;
        chunkDataTmp.Size = chunkSize;
        chunkDataTmp.Visible = AABBInsideFrustum(min, max);
        chunkDataTmp.Free = 1;
        chunkData[index] = chunkDataTmp;
    }
}
