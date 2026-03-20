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
        int2 Grid;
        float Size;
        int Visible;
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
	float3 playerPosition < Attribute("PlayerPosition"); >;

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

    [numthreads(8, 1, 1)]
    void MainCs(uint3 id: SV_DispatchThreadID)
    {
        uint index = id.x;
        int gridSize = worldChunkPerRow;
        int totalChunks = gridSize * gridSize;

        if (index >= totalChunks)
            return;

        float chunkSize = 1000.0f;   // Constant for now
        int halfGrid = gridSize / 2; // 2

        float2 localPlayerPosition = float2(playerPosition.xy - terrainPosition.xy);
        float2 camForward = float2(g_vCameraDirWs.x, g_vCameraDirWs.y);
        float gridExtent = (gridSize * chunkSize) * 0.5f;
        float2 offsetCenter = localPlayerPosition; // + camForward * gridExtent * 0.5;

        int2 playerChunk = int2(floor(offsetCenter.x / chunkSize), floor(offsetCenter.y / chunkSize));

        int localX = (index % gridSize) - halfGrid;
        int localY = (index / gridSize) - halfGrid;

        int2 gridCoord = playerChunk + int2(localX, localY);

        float3 terrainCenter = terrainPosition + float3(terrainSize.x, terrainSize.y, 0) * 0.5;
        float worldX = terrainCenter.x + localX * chunkSize + chunkSize * 0.5;
        float worldY = terrainCenter.x + localY * chunkSize + chunkSize * 0.5;

        float3 min = float3(worldX - chunkSize * 0.5, worldY - chunkSize * 0.5, terrainPosition.z);
        float3 max = float3(worldX + chunkSize * 0.5, worldY + chunkSize * 0.5, terrainPosition.z + terrainSize.x);

        ChunkData chunkDataTmp;
        chunkDataTmp.Position = float2(worldX, worldY);
        chunkDataTmp.Grid = gridCoord;
        chunkDataTmp.Size = chunkSize;
        chunkDataTmp.Visible = AABBInsideFrustum(min, max);
        chunkData[index] = chunkDataTmp;
    }
}
