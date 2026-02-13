MODES
{
    Default();
}

CS
{
	#include "system.fxc"
	
	struct GrassData
	{
		float3 Position;	
		float3 Normal;		
		float  Rotation;	
		float  Stiffness;
		float  BendAmount;	
		float BladeHash;
		float DistanceFromCamera;
	};		

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

	static const float PI = 3.14159265359;

	float Hash(uint seed)
	{
		seed = (seed ^ 61) ^ (seed >> 16);
		seed *= 9;
		seed = seed ^ (seed >> 4);
		seed *= 0x27d4eb2d;
		seed = seed ^ (seed >> 15);
		return float(seed) / 4294967296.0; 
	}

	float HashXY(float x, float y)
	{
		return frac(sin(x * 12.9898f + y * 78.233f) * 43758.5453f);
	}

	float HashXY(float2 value)
	{
		return frac(sin(value.x * 12.9898f + value.y * 78.233f) * 43758.5453f);
	}

	float Hash12(float2 p)
	{
		float3 p3 = frac(float3(p.xyx) * 0.1031);
		p3 += dot(p3, p3.yzx + 33.33);
		return frac((p3.x + p3.y) * p3.z);
	}
	
	float Random(uint seed, float minVal, float maxVal)
	{
		return minVal + Hash(seed) * (maxVal - minVal);
	}

	float2 GetClumpOffset(float2 worldPos, uint seed)
	{
		float2 clumpCell = floor(worldPos / clumpSize);
    
		float clumpHash = HashXY(clumpCell.x * 73.0f, clumpCell.y * 149.0f) * Hash(seed);
		float2 clumpCenterOffset = float2(frac(clumpHash * 12.9898f),frac(clumpHash * 78.233f)) * clumpSize;
    
		float2 clumpCenter = clumpCell * clumpSize + clumpCenterOffset;
    
		float2 toClump = clumpCenter - worldPos;
		float distToClump = length(toClump);
    
		float falloff = saturate(1.0 - (distToClump / (clumpSize * 0.5f)));
		falloff = falloff * falloff; 
    
		return toClump * clumpStrength * falloff;
	}

	bool InsideCameraFrustrum(float3 center)
	{
		for (int i = 0; i < 6; i++)
		{
			if(dot(planes[i].Normal, center) - planes[i].Distance < 0) return false;
		}
		
		return true;
	}

	AppendStructuredBuffer<GrassData> grassHighLod < Attribute( "GrassHighLodData" ); >;
	AppendStructuredBuffer<GrassData> grassLowLod < Attribute( "GrassLowLodData" ); >;

	RWStructuredBuffer<ChunkData> chunkBuffer <Attribute("ChunkData"); >;

	Texture2D<float> _HeightMap <Attribute("HeightMap"); >;

	int grassCount <Attribute("GrassCount"); >;

	float time <Attribute("time"); >;
	
	float3 terrainPosition < Attribute("TerrainPosition"); >;
	
	float3 cameraPosition < Attribute("CameraPosition"); >;
	
	int grassPerChunk < Attribute("grassPerChunk"); >;

	float subChunkSize < Attribute("SubChunksSize"); >;
	int subChunksPerRow < Attribute("SubChunksPerRow"); >;

	float2 terrainSize <Attribute("TerrainSize"); >;
	
	float clumpStrength < Attribute("ClumpStrength"); Default(0.3f); >;
	
	float clumpSize < Attribute("ClumpSize"); Default(3.0f); >;

	float2 GetJitteredPosition(uint index, float2 centerOfChunk, float2 halfChunk)
	{
		float jitterX = Random(index * 13u + time, -halfChunk.x, halfChunk.x);
		float jitterY = Random(index * 31u + time, -halfChunk.y, halfChunk.y);
		float2 worldXY = float2(centerOfChunk.x + jitterX, centerOfChunk.y + jitterY);
		return worldXY + GetClumpOffset(centerOfChunk, index);
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
		GrassData grassData;
		grassData.Position   = grassPosition;
		grassData.Rotation   = Random(index * 17u, -2.0f * PI, 2.0f * PI);
		grassData.BendAmount = Random(index * 23u, 0.1f, 0.35f);
		grassData.Stiffness  = Random(index * 12u, 0.2f, 1.0f);
		grassData.Normal	 = normal;
		grassData.BladeHash  = bladeHash;
		grassData.DistanceFromCamera = dist;
		return grassData;
	}

	void AppendToBuffer(GrassData grassData, float dist, float bladeHash)
	{
		const float lodTransitionDist = 2500 + bladeHash * 3000.0f;

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
    void MainCs(uint3 id : SV_DispatchThreadID)
    {
        uint index = id.x;

		if(index >= grassCount) return;

		uint chunkIndex = index / grassPerChunk;

		ChunkData chunkData = chunkBuffer[chunkIndex]; 

		//float subHalfChunkSize = subChunkSize * 0.5f;

		//float2 subChunkOffset = GetSubChunkOffset(index, subHalfChunkSize);

		//float2 halfChunk = chunkSize * 0.5f;

		//float2 chunkOffset = GetChunkOffset(index, chunksPerRow, chunkSize, halfChunk);

		float2 centerOfChunk = terrainPosition.xy + chunkData.Position;

		float2 worldXY = GetJitteredPosition(index, centerOfChunk, chunkData.Size * 0.5);
		
		worldXY += GetClumpOffset(worldXY, index);

		uint texWidth, texHeight;
		_HeightMap.GetDimensions(texWidth, texHeight);

		uint2 texel = WorldToTexel(worldXY, texWidth, texHeight);

		float texelSizeWorld = terrainSize.x / (texWidth - 1);

		float height = SampleHeight(texel);

		float3 grassPosition = float3(worldXY.x, worldXY.y, height + terrainPosition.z);

		if(!InsideCameraFrustrum(grassPosition)) return;

		float dist = distance(cameraPosition, grassPosition);

		const float endDistance = 20000;

		if (dist > endDistance) return;

		float bladeHash = Hash12(worldXY);

		float densityThreshold = CalculateDensityThreshold(dist);

		if (bladeHash > densityThreshold) return;

		TerrainNormalData terrainData = CalculateTerrainNormal(texel, texWidth, texHeight, texelSizeWorld);
		
		if(terrainData.SlopeAngle > 90.0) return;

		GrassData grassData = CreateGrassData(index, grassPosition, terrainData.Normal, bladeHash, dist);

		AppendToBuffer(grassData, dist, bladeHash);
    }
}