MODES
{
    Default();
}

CS
{
    // clang-format off

    #include "system.fxc"
    #include "common/shared.hlsl"
    #include "utilities.hlsl"

    // clang-format on
    struct GrassData
    {
        float3 Position;
        float _pad0;
        float3 Normal;
        float _pad1;
        float4 Color;
        float2 Rotation;
        float Stiffness;
        float BendAmount;
        float BladeHash;
        float DistanceFromCamera;
    };

    struct ChunkData
    {
        float2 Position;
        int2 Grid;
        float Size;
        int Visible;
    };

    struct SubChunkData
    {
        float2 Position;
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

    static const float PI = 3.14159265359;

    bool InsideCameraFrustrum(float3 center)
    {
        for (int i = 0; i < 6; i++)
        {
            if (dot(planes[i].Normal, center) - planes[i].Distance < 0)
                return false;
        }

        return true;
    }

    bool PositionVisibleAt(float3 pos)
    {
        if (!InsideCameraFrustrum(pos))
            return false;

        float4 clipPos = Position3WsToPs(pos);

        clipPos.xyz /= clipPos.w;

        // Depth test
        float2 uv = clipPos.xy * 0.5f + 0.5f; // [0,1] range
        uv.y = 1.0f - uv.y;                   // flip Y for texture coords

        float flDepth = Depth::Normalize(g_tDepthChain.SampleLevel(g_sPointWrap, uv, 5.0f).x);

        if (flDepth > clipPos.z)
            return false; // culled by depth

        return true;
    }

    // clang-format off
	AppendStructuredBuffer<GrassData> grassHighLod < Attribute( "GrassHighLodData" ); >;
	AppendStructuredBuffer<GrassData> grassLowLod < Attribute( "GrassLowLodData" ); >;

	RWStructuredBuffer<ChunkData> chunkBuffer <Attribute("ChunkData"); >;

	int subChunkCountPerChunk <Attribute("SubChunkCountPerChunk"); >;

	Texture2D<float> _HeightMap <Attribute("HeightMap"); >;

	int grassCount <Attribute("GrassCount"); >;

	float time <Attribute("time"); >;
	
	float3 terrainPosition < Attribute("TerrainPosition"); >;
	
	float subChunkSize < Attribute("SubChunkSize"); >;

	int totalChunks < Attribute("TotalWorldChunks"); >;

	float2 terrainSize <Attribute("TerrainSize"); >;

   Texture2D terrainControlMap < Attribute("TerrainControlMap"); >;

    // clang-format on

    uint2 WorldToTexel(float2 worldXY, uint texWidth, uint texHeight)
    {
        float2 uv = (worldXY - terrainPosition.xy) / terrainSize.x;

        if (uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1)
            return uint2(-9999, -9999);

        return uint2(uv.x * (texWidth - 1), uv.y * (texHeight - 1));
    }

    float SampleHeight(uint2 texel)
    {
        return _HeightMap.Load(int3(texel.x, texel.y, 0)).r * terrainSize.y;
    }

    struct TerrainNormalData
    {
        float3 Normal;
        float SlopeAngle;
    };

    TerrainNormalData CalculateTerrainNormal(uint2 texel, uint texWidth, uint texHeight, float texelSizeWorld)
    {
        uint leftX = (texel.x == 0) ? 0 : texel.x - 1;
        uint rightX = (texel.x == texWidth - 1) ? texel.x : texel.x + 1;
        uint bottomY = (texel.y == 0) ? 0 : texel.y - 1;
        uint topY = (texel.y == texHeight - 1) ? texel.y : texel.y + 1;

        float heightLeft = _HeightMap.Load(int3(leftX, texel.y, 0)).r;
        float heightRight = _HeightMap.Load(int3(rightX, texel.y, 0)).r;
        float heightBottom = _HeightMap.Load(int3(texel.x, bottomY, 0)).r;
        float heightTop = _HeightMap.Load(int3(texel.x, topY, 0)).r;

        float horizontalDist = 2.0 * texelSizeWorld;

        float dx = (heightRight - heightLeft) * terrainSize.y / horizontalDist;
        float dy = (heightTop - heightBottom) * terrainSize.y / horizontalDist;

        float slopeMagnitude = length(float2(dx, dy));

        TerrainNormalData result;
        result.Normal = normalize(float3(-dx, -dy, 1.0));
        result.SlopeAngle = degrees(atan(slopeMagnitude));

        return result;
    }

    float CalculateDensityThreshold(float dist)
    {
        const float startDistance = 100;
        const float endDistance = 10000;
        return 1.0 - saturate((dist - startDistance) / (endDistance - startDistance));
    }

    GrassData CreateGrassData(uint index, float3 grassPosition, float3 normal, float bladeHash, float clumpHash, float dist)
    {
        uint seed = index;

        float facingAngle = Hash01(seed * 7919u) * 6.28318; // 0‑2π
        float2 facing = float2(cos(facingAngle), sin(facingAngle));

        // Add clumping behavior - grass tends to grow in similar directions locally
        float2 clumpCenter = floor(grassPosition.xy / 2.0) * 2.0; // 2m clumps
        uint clumpSeed = Hash(uint(clumpCenter.x * 1000.0 + clumpCenter.y * 73856093.0));
        float clumpAngle = Hash01(clumpSeed + time) * 6.28318;
        float2 clumpFacing = float2(cos(clumpAngle), sin(clumpAngle));

        // Blend individual and clump facing (more clumped look)
        float clumpStrength = 0.1; // How much grass follows clump direction
        facing = normalize(lerp(facing, clumpFacing, clumpStrength));

        GrassData grassData;
        grassData.Position = grassPosition;
        grassData.Rotation = facing;

        float clumpBendBase = lerp(0.5, 1.2, clumpHash);
        grassData.BendAmount = clumpBendBase + (Hash01(index + 444u) - 0.5) * 0.3;

        float clumpStiffnessBase = lerp(0.4, 0.8, clumpHash);
        grassData.Stiffness = clumpStiffnessBase + (Hash01(index + 333u) - 0.5) * 0.2;

        grassData.Normal = normal;
        grassData.BladeHash = bladeHash + clumpHash;
        grassData.DistanceFromCamera = dist;

        return grassData;
    }

    void AppendToBuffer(GrassData grassData, float dist, float bladeHash)
    {
        const float lodTransitionDist = 1500 + bladeHash * 2000.0f;

        if (dist < lodTransitionDist)
        {
            grassHighLod.Append(grassData);
        }
        else
        {
            grassLowLod.Append(grassData);
        }
    }

    // What ghost of Tsushima did, they talked about how this should improve the "randomness" of grass
    float2 VoronoiClump(float2 pos, float scale, out float distToCenter)
    {
        float2 scaledPos = pos / scale;
        float2 cell = floor(scaledPos);
        float2 cellFrac = scaledPos - cell;

        float minDist = 9999.0;
        float2 closestPoint = float2(0, 0);

        for (int y = -1; y <= 1; y++)
        {
            for (int x = -1; x <= 1; x++)
            {
                float2 neighbor = float2(x, y);
                float2 neighborCell = cell + neighbor;

                float2 jitter = float2(Hash01(uint(neighborCell.x * 73856093 + neighborCell.y * 19349663)), Hash01(uint(neighborCell.x * 19349663 + neighborCell.y * 83492791))) * 0.8;

                float2 jitteredPoint = neighbor + jitter;
                float d = length(cellFrac - jitteredPoint);

                if (d < minDist)
                {
                    minDist = d;
                    closestPoint = neighborCell + jitter;
                }
            }
        }

        distToCenter = minDist;
        return closestPoint;
    }

    [numthreads(64, 1, 1)]
    void MainCs(uint3 id: SV_DispatchThreadID)
    {
        uint index = id.x;

        if (index >= grassCount)
            return;

        uint bladesPerChunk = 8000;

        float cellSize = 700 / sqrt((float)bladesPerChunk);

        uint chunkIndex = index / bladesPerChunk;
        uint localIndex = index % bladesPerChunk;

        if (chunkIndex >= totalChunks)
            return;

        ChunkData chunk = chunkBuffer[chunkIndex];

        if (chunk.Visible == 0)
            return;

        uint cellsPerRow = chunk.Size / cellSize;

        uint cellX = localIndex % cellsPerRow;
        uint cellY = localIndex / cellsPerRow;

        int worldCellX = chunk.Grid.x * cellsPerRow + cellX;
        int worldCellY = chunk.Grid.y * cellsPerRow + cellY;

        uint bladeSeed = (uint)(worldCellX * 73856093) ^ (uint)(worldCellY * 19349663);

        float2 chunkMin = chunk.Position - chunk.Size * 0.5;

        float2 basePos = chunkMin + float2(cellX * cellSize, cellY * cellSize);

        float2 jitter = float2((Hash01(bladeSeed + 111u) - 0.5f) * cellSize, (Hash01(bladeSeed + 222u) - 0.5f) * cellSize);

        float2 worldXY = basePos + jitter;

        float clumpDist;
        float clumpScale = 15;
        float2 clumpCenter = VoronoiClump(worldXY, clumpScale, clumpDist);

        // Pull position toward clump center
        float clumpPull = 0.3; // 0 = no pull, 1 = all blades at center
        worldXY = lerp(worldXY, clumpCenter * clumpScale, clumpPull * (1.0 - clumpDist));

        float spawnChance = 1.0 - smoothstep(0.6, 1, clumpDist);

        if (Hash01(bladeSeed + 777u) > spawnChance)
            return;

        uint texWidth, texHeight;
        _HeightMap.GetDimensions(texWidth, texHeight);

        uint2 texel = WorldToTexel(worldXY, texWidth, texHeight);

        if (texel.x == -9999 && texel.y == -9999)
            return;

        float height = SampleHeight(texel);

        float3 grassPosition = float3(worldXY.xy, height + terrainPosition.z);

        if (!PositionVisibleAt(grassPosition))
            return;

        float dist = distance(g_vCameraPositionWs, grassPosition);

        const float endDistance = 10000;

        if (dist > endDistance)
            return;

        float densityThreshold = CalculateDensityThreshold(dist);

        float bladeRandom = Hash01(bladeSeed);

        if (Hash01(index) > densityThreshold)
            return;

        float texelSizeWorld = terrainSize.x / (texWidth - 1);

        TerrainNormalData terrainData = CalculateTerrainNormal(texel, texWidth, texHeight, texelSizeWorld);

        if (terrainData.SlopeAngle > 45.0)
            return;

        float clumpHash = Hash01(uint(clumpCenter.x * 127 + clumpCenter.y * 311));

        GrassData grassData = CreateGrassData(bladeSeed, grassPosition, terrainData.Normal, bladeRandom, clumpHash, dist);

        AppendToBuffer(grassData, dist, clumpHash);
    }
}
