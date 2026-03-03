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
	

    // clang-format on

    uint2 WorldToTexel(float2 worldXY, uint texWidth, uint texHeight)
    {
        float2 uv = (worldXY - terrainPosition.xy) / terrainSize.x;

        if (uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1)
            return uint2(0, 0);

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

        float slopeMagnitude = length(float2(dx, dy)) / horizontalDist;

        TerrainNormalData result;
        result.Normal = normalize(float3(-dx / horizontalDist, -dy / horizontalDist, 1.0));
        result.SlopeAngle = degrees(atan(slopeMagnitude));

        return result;
    }

    float CalculateDensityThreshold(float dist)
    {
        const float startDistance = 1500;
        const float endDistance = 10000;
        return 1.0 - saturate((dist - startDistance) / (endDistance - startDistance));
    }

    GrassData CreateGrassData(uint index, float3 grassPosition, float3 normal, float bladeHash, float dist)
    {
        uint seed = index;

        float facingAngle = Hash01(seed * 7919u).x * 6.28318; // 0‑2π
        float2 facing = float2(cos(facingAngle), sin(facingAngle));

        // Add clumping behavior - grass tends to grow in similar directions locally
        float2 clumpCenter = floor(grassPosition.xy / 2.0) * 2.0; // 2m clumps
        uint clumpSeed = Hash(uint(clumpCenter.x * 1000.0 + clumpCenter.y * 73856093.0));
        float clumpAngle = Hash01(clumpSeed) * 6.28318;
        float2 clumpFacing = float2(cos(clumpAngle), sin(clumpAngle));

        // Blend individual and clump facing (more clumped look)
        float clumpStrength = 0.2; // How much grass follows clump direction
        facing = normalize(lerp(facing, clumpFacing, clumpStrength));

        GrassData grassData;
        grassData.Position = grassPosition;
        grassData.Color = float4(1, 1, 1, 1);
        grassData.Rotation = facing;
        grassData.BendAmount = Random(seed, 0.5, 1.5f);
        grassData.Stiffness = Random(seed, 0.1f, 0.8f);
        grassData.Normal = normal;
        grassData.BladeHash = bladeHash + Hash01(index);
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

    [numthreads(64, 1, 1)]
    void MainCs(uint3 id: SV_DispatchThreadID)
    {
        uint index = id.x;

        if (index >= grassCount)
            return;

        float cellSize = 10.0;

        uint bladesPerChunk = 4900;

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

        uint texWidth, texHeight;
        _HeightMap.GetDimensions(texWidth, texHeight);

        uint2 texel = WorldToTexel(worldXY, texWidth, texHeight);

        if (texel.x == 0 && texel.y == 0)
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
        
        float bladeRandom = Hash01(bladeSeed + 789u);
        
        if (bladeRandom > densityThreshold)
         return;
        
        float texelSizeWorld = terrainSize.x / (texWidth - 1);

        TerrainNormalData terrainData = CalculateTerrainNormal(texel, texWidth, texHeight, texelSizeWorld);

        if (terrainData.SlopeAngle > 90.0)
            return;

        GrassData grassData = CreateGrassData(bladeSeed, grassPosition, terrainData.Normal, bladeRandom, dist);

        AppendToBuffer(grassData, dist, bladeRandom);
    }
}
