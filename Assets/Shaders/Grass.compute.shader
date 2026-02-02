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
		float  BendAmount;	
		float  Noise;        
		bool   ShouldDiscard;
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

	
	float Random(uint seed, float minVal, float maxVal)
	{
		return minVal + Hash(seed) * (maxVal - minVal);
	}

	float2 GetClumpOffset(float2 worldPos, uint seed)
	{
		float2 clumpCell = floor(worldPos / clumpSize);
    
		float clumpHash = HashXY(clumpCell.x * 73.0f, clumpCell.y * 149.0f);
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


	AppendStructuredBuffer<GrassData> grass < Attribute( "GrassData" ); >;

	Texture2D<float> _HeightMap <Attribute("HeightMap"); >;

	int grassCount <Attribute("GrassCount"); >;

	float time <Attribute("time"); >;

	float3 terrainPosition < Attribute("TerrainPosition"); >;

	float2 chunkSize < Attribute("ChunkSize"); >;

	int chunkCount < Attribute("ChunkCount"); >;

	float clumpStrength < Attribute("ClumpStrength"); Default(0.3f); >;

	float clumpSize < Attribute("ClumpSize"); Default(3.0f); >;

	[numthreads(64, 1, 1)]
    void MainCs(uint3 id : SV_DispatchThreadID)
    {
        uint index = id.x;
        
		if (index >= grassCount) return;

		uint grassPerChunk = grassCount / chunkCount;

		uint chunkIndex = index / grassPerChunk;

		uint chunksPerRow = (uint)sqrt(chunkCount);

		uint chunkIndexX = chunkIndex % chunksPerRow;
		uint chunkIndexY = chunkIndex / chunksPerRow;

		float2 halfChunk = chunkSize * 0.5f;

        float jitterX = Random(index * 13u + time, -halfChunk.x, halfChunk.x);
        float jitterY = Random(index * 31u + time, -halfChunk.y, halfChunk.y);

		float2 chunkOffset = float2(chunkIndexX * chunkSize.x, chunkIndexY * chunkSize.y) + halfChunk;

		float2 centerOfChunk = terrainPosition.xy + chunkOffset;

        float2 worldXY = float2(centerOfChunk.x + jitterX, centerOfChunk.y + jitterY);

		//worldXY += GetClumpOffset(centerOfChunk, index);
		
		uint texWidth, texHeight;
		_HeightMap.GetDimensions(texWidth, texHeight);

		float2 terrainSize = chunkSize * chunksPerRow;

		float2 uv = (worldXY - terrainPosition.xy) / terrainSize;
		uint2 texel = uint2(uv.x * (texWidth - 1), uv.y * (texHeight - 1));

		float height = _HeightMap.Load(int3(texel.x, texel.y, 0)).r * terrainSize.x;

		if(!InsideCameraFrustrum(float3(worldXY, height + terrainPosition.z))) return;

		float texelSizeWorld = terrainSize.x / texWidth;
    
		uint leftX = (texel.x == 0) ? 0 : texel.x - 1;
		uint rightX = (texel.x == texWidth - 1) ? texel.x : texel.x + 1;
		uint bottomY = (texel.y == 0) ? 0 : texel.y - 1;
		uint topY = (texel.y == texHeight - 1) ? texel.y : texel.y + 1;
		
		float heightLeft = _HeightMap.Load(int3(leftX, texel.y, 0));
		float heightRight = _HeightMap.Load(int3(rightX, texel.y, 0));
		float heightBottom = _HeightMap.Load(int3(texel.x, bottomY, 0));
		float heightTop = _HeightMap.Load(int3(texel.x, topY, 0));			

		float dx = heightRight - heightLeft;
		float dy = heightTop - heightBottom;

        GrassData grassData;

        grassData.Position   = float3(worldXY.x, worldXY.y, height + terrainPosition.z);
        grassData.Rotation   = Random(index * 17u + time, -2.0f * PI, 2.0f * PI);
        grassData.BendAmount = Random(index * 23u + time, 0.03f, 0.1f);
		grassData.Normal	 = normalize(float3(-dx, -dy, 2.0));
		grassData.Noise		 = HashXY(worldXY.x, worldXY.y);
        
		grass.Append(grassData);
    }
}