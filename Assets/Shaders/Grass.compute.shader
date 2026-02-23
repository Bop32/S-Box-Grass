MODES
{
    Default();
}

CS
{
	#include "system.fxc"
	#include "common/shared.hlsl"
   #include "common/Bindless.hlsl"
   
	struct GrassData
	{
		float3 Position;	
		float3 Normal;		
      float3 Color;
		float2  Rotation;	
		float  Stiffness;
		float  BendAmount;	
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

		int ParentChunkIndex;
		int Visible;
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


	bool InsideCameraFrustrum(float3 center)
	{
		for (int i = 0; i < 6; i++)
		{
			if(dot(planes[i].Normal, center) - planes[i].Distance < 0) return false;
		}
		
		return true;
	}

	bool PositionVisibleAt(float3 pos)
    {
      if (!InsideCameraFrustrum(pos)) return false;

		float4 clipPos = Position3WsToPs(pos);

		clipPos.xyz /= clipPos.w;

      // Depth test
      float2 uv = clipPos.xy * 0.5f + 0.5f; // [0,1] range
      uv.y = 1.0f - uv.y; // flip Y for texture coords
      
      float flDepth = Depth::Normalize( g_tDepthChain.SampleLevel( g_sPointWrap, uv, 5.0f ).x ) ;

      if(flDepth > clipPos.z) return false; // culled by depth

      return true;
	}

	AppendStructuredBuffer<GrassData> grassHighLod < Attribute( "GrassHighLodData" ); >;
	AppendStructuredBuffer<GrassData> grassLowLod < Attribute( "GrassLowLodData" ); >;

	RWStructuredBuffer<ChunkData> chunkBuffer <Attribute("ChunkData"); >;
	RWStructuredBuffer<SubChunkData> subChunkBuffer <Attribute("SubChunkData"); >;

	int subChunkCountPerChunk <Attribute("SubChunkCountPerChunk"); >;

	Texture2D<float> _HeightMap <Attribute("HeightMap"); >;

	int grassCount <Attribute("GrassCount"); >;

	float time <Attribute("time"); >;
	
	float3 terrainPosition < Attribute("TerrainPosition"); >;
	
	int grassPerChunk < Attribute("grassPerChunk"); >;

	int totalChunks < Attribute("TotalWorldChunks"); >;

	float2 terrainSize <Attribute("TerrainSize"); >;
	
	//float clumpStrength < Attribute("ClumpStrength"); Default(0.3f); >;
	
	//float clumpSize < Attribute("ClumpSize"); Default(3.0f); >;

	float2 GetJitteredPosition(uint index, float2 centerOfChunk, float chunkSize)
	{
		float halfChunk = chunkSize * 0.5;

		float jitterX = Random(index * 13u, -halfChunk, halfChunk);
		float jitterY = Random(index * 31u, -halfChunk, halfChunk);
		float2 worldXY = float2(centerOfChunk.x + jitterX, centerOfChunk.y + jitterY);

		return worldXY;
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
		grassData.Position   = grassPosition;
		grassData.Rotation   = facing;
		grassData.BendAmount = Random(seed * bladeHash, 0.5, 1.5f);
		grassData.Stiffness  = Random(seed * bladeHash, 0.1f, 0.8f);
		grassData.Normal	 = normal;
		grassData.BladeHash  = bladeHash;
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

	struct DistributionResult
	{
		uint GroupIndex;
		uint LocalIndex;
		uint GroupSize;
	};

	DistributionResult GetDistributedIndexAndLocal(uint index, uint totalItems, uint groupCount)
	{
		DistributionResult result;
		
		uint base = totalItems / groupCount;
		uint remainder = totalItems % groupCount;

		uint threshold = (base + 1) * remainder;

		if (index < threshold)
		{
			result.GroupIndex = index / (base + 1);
			result.LocalIndex = index % (base + 1);
			result.GroupSize  = base + 1;
			return result;
		}
			
		uint adjusted = index - threshold;
		result.GroupIndex = remainder + adjusted / base;
		result.LocalIndex = adjusted % base;
		result.GroupSize = base;

		return result;
	}


	[numthreads(64, 1, 1)]
    void MainCs(uint3 id : SV_DispatchThreadID)
    {
		uint index = id.x;

		if(index > grassCount) return;

		DistributionResult worldChunks = GetDistributedIndexAndLocal(index, grassCount, totalChunks);

		ChunkData chunkData = chunkBuffer[worldChunks.GroupIndex];

		if(!chunkData.Visible) return;

		DistributionResult subChunks = GetDistributedIndexAndLocal(worldChunks.LocalIndex, worldChunks.GroupSize, subChunkCountPerChunk);
		
		uint globalSubChunkIndex = worldChunks.GroupIndex * subChunkCountPerChunk + subChunks.GroupIndex;
		
		SubChunkData subChunkData = subChunkBuffer[globalSubChunkIndex];

		if(!subChunkData.Visible) return;

		float2 centerOfChunk = subChunkData.Position;
	
		float2 worldXY = GetJitteredPosition(index, centerOfChunk, subChunkData.Size);

		uint texWidth, texHeight;
		_HeightMap.GetDimensions(texWidth, texHeight);

		uint2 texel = WorldToTexel(worldXY, texWidth, texHeight);

		float height = SampleHeight(texel);

		float texelSizeWorld = terrainSize.x / (texWidth - 1);
		
		float3 grassPosition = float3(worldXY.x, worldXY.y, height + terrainPosition.z);

		if(!PositionVisibleAt(grassPosition)) return;

		float dist = distance(g_vCameraPositionWs, grassPosition);

		const float endDistance = 10000;

		if (dist > endDistance) return;

		float bladeHash = Hash01(index);

		float densityThreshold = CalculateDensityThreshold(dist);

		if (bladeHash > densityThreshold) return;

		TerrainNormalData terrainData = CalculateTerrainNormal(texel, texWidth, texHeight, texelSizeWorld);
		
		if(terrainData.SlopeAngle > 90.0) return;

		GrassData grassData = CreateGrassData(index, grassPosition, terrainData.Normal, bladeHash, dist);

		AppendToBuffer(grassData, dist, bladeHash);
    }
}