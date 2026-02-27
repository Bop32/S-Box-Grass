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
    struct GrassData
    {
        float3 Position;
        float3 Normal;
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
        float Size;
        int Visible;
        int Free;
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

    uint Hash(uint n)
    {
        n ^= n >> 16;
        n *= 0x7feb352d;
        n ^= n >> 15;
        n *= 0x846ca68b;
        n ^= n >> 16;
        return n;
    }

    float Hash01(uint n)
    {
        return (Hash(n) & 0x00FFFFFFu) / 16777215.0;
    }

    float2 Hash02(uint n)
    {
        uint h = Hash(n);
        return float2((h & 0xFFFFu), (h >> 16)) / 65535.0;
    }

    float Random(uint seed, float minVal, float maxVal)
    {
        return minVal + Hash01(seed) * (maxVal - minVal);
    }

    float2 Random2(uint seed, float minVal, float maxVal)
    {
        return float2(minVal + Hash01(seed) * (maxVal - minVal), minVal + Hash01(seed + 1u) * (maxVal - minVal));
    }

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

	RWStructuredBuffer<SubChunkData> subChunkBuffer <Attribute("SubChunkData"); >;

	int subChunkCountPerChunk <Attribute("SubChunkCountPerChunk"); >;

	Texture2D<float> _HeightMap <Attribute("HeightMap"); >;

	int grassCount <Attribute("GrassCount"); >;

	float time <Attribute("time"); >;
	
	float3 terrainPosition < Attribute("TerrainPosition"); >;
	
	float subChunkSize < Attribute("SubChunkSize"); >;

	int totalChunks < Attribute("TotalWorldChunks"); >;

	float2 terrainSize <Attribute("TerrainSize"); >;
	
	//float clumpStrength < Attribute("ClumpStrength"); Default(0.3f); >;
	
	//float clumpSize < Attribute("ClumpSize"); Default(3.0f); >;

    // clang-format on

    float2 GetPositionInClump(uint index, float2 centerOfChunk, float chunkSize)
    {
        float halfChunk = chunkSize * 0.5;
        float2 macroClump = centerOfChunk + Random2(index, -halfChunk, halfChunk);

        float microRadius = chunkSize * 0.0001; // micro clumps within 10% of chunk size
        float angle = Hash01(index * 13u) * 6.28318;
        float radius = Hash01(index * 31u) * microRadius;
        float2 microOffset = float2(cos(angle), sin(angle)) * radius;

        return macroClump + microOffset;
    }

    uint2 WorldToTexel(float2 worldXY, uint texWidth, uint texHeight)
    {
        float2 uv = (worldXY - terrainPosition.xy) / terrainSize.x;
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

        float dx = (heightRight - heightLeft) * terrainSize.x;
        float dy = (heightTop - heightBottom) * terrainSize.x;

        float horizontalDist = 2.0 * texelSizeWorld;
        float slopeMagnitude = length(float2(dx, dy)) / horizontalDist;

        TerrainNormalData result;
        result.Normal = normalize(float3(-dx, -dy, 2.0 * texelSizeWorld));
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
        uint seed = index * 9781u + 231u; // any large coprime numbers

        float facingAngle = Hash02(seed * 128u).x * 6.28318; // 0‑2π
        float2 facing = float2(cos(facingAngle), sin(facingAngle));

        // Add clumping behavior - grass tends to grow in similar directions locally
        float2 clumpCenter = floor(grassPosition.xy / 2.0) * 2.0; // 2m clumps
        uint clumpSeed = Hash01(uint(clumpCenter.x * 1000 + clumpCenter.y));
        float clumpAngle = Hash01(clumpSeed) * 6.28318;
        float2 clumpFacing = float2(cos(clumpAngle), sin(clumpAngle));

        // Blend individual and clump facing (more clumped look)
        float clumpStrength = 0.4; // How much grass follows clump direction
        facing = normalize(lerp(facing, clumpFacing, clumpStrength));

        GrassData grassData;
        grassData.Position = grassPosition;
        grassData.Color = float4(1, 1, 1, 1);
        grassData.Rotation = facing;
        grassData.BendAmount = Random(seed, 0.5, 1.5f);
        grassData.Stiffness = Random(seed, 0.1f, 0.8f);
        grassData.Normal = normal;
        grassData.BladeHash = Hash01(seed);
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

        float cellSize = 8.0;

        uint cellsPerRow = subChunkSize / cellSize;
        uint bladesPerSubchunk = cellsPerRow * cellsPerRow;
        uint bladesPerChunk = subChunkCountPerChunk * subChunkCountPerChunk * bladesPerSubchunk;
        uint subChunkIndex = (index % bladesPerChunk) / bladesPerSubchunk; // which subchunk in the current chunk
        uint localIndex = index % bladesPerSubchunk;                       // blade inside that subchunk

        SubChunkData subChunkData = subChunkBuffer[subChunkIndex];

        if (!subChunkData.Visible)
            return;

        float2 centerOfChunk = subChunkData.Position;

        uint cellX = localIndex % cellsPerRow;
        uint cellY = localIndex / cellsPerRow;

        float jitterX = Random(index + 123u, -0.4f, 0.4f);
        float jitterY = Random(index + 456u, -0.4f, 0.4f);

        float chunkSize = subChunkData.Size;

        float worldX = chunkSize - (cellX + 0.5f + jitterX) * cellSize;
        float worldY = chunkSize - (cellY + 0.5f + jitterY) * cellSize;

        float2 worldXY = centerOfChunk + float2(worldX, worldY);

        uint texWidth, texHeight;
        _HeightMap.GetDimensions(texWidth, texHeight);

        uint2 texel = WorldToTexel(worldXY, texWidth, texHeight);

        float height = SampleHeight(texel);

        float texelSizeWorld = terrainSize.x / (texWidth - 1);

        float3 grassPosition = float3(worldXY.xy, height + terrainPosition.z);

        if (!PositionVisibleAt(grassPosition))
            return;

        float dist = distance(g_vCameraPositionWs, grassPosition);

        const float endDistance = 10000;

        if (dist > endDistance)
            return;

        uint hash = Hash01(index * 997u + 123u); // any large coprime numbers

        float densityThreshold = CalculateDensityThreshold(dist);

        if (hash > densityThreshold)
            return;

        TerrainNormalData terrainData = CalculateTerrainNormal(texel, texWidth, texHeight, texelSizeWorld);

        if (terrainData.SlopeAngle > 90.0)
            return;

        GrassData grassData = CreateGrassData(index, grassPosition, terrainData.Normal, hash, dist);

        AppendToBuffer(grassData, dist, hash);
    }
}
