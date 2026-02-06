FEATURES
{
    #include "common/features.hlsl"
}
MODES
{
    Forward();
    Depth();
}
COMMON
{
	#include "common/shared.hlsl"
	#include "procedural.hlsl"
	
}
struct VertexInput
{
	#include "common/vertexinput.hlsl"
	uint nInstanceID : SV_InstanceID;
};
struct PixelInput
{
	#include "common/pixelinput.hlsl"
};
VS
{
	#include "common/vertex.hlsl"
	
	struct GrassData
	{
		float3 Position;	
		float3 Normal;		
		float  Rotation;
		float Stiffness;
		float  BendAmount;	
	};	

	StructuredBuffer<GrassData> GrassInstanceData < Attribute( "GrassData" ); >;

	float3 cameraPosition < Attribute("CameraPosition"); >;

	float Hash12(float2 p)
	{
		float3 p3 = frac(float3(p.xyx) * 0.1031);
		p3 += dot(p3, p3.yzx + 33.33);
		return frac((p3.x + p3.y) * p3.z);
	}


	float CalculateWind(float3 grassPosition)
	{
		const float windSpeed = 0.1f;
		const float flowScale = 0.1f;

		const float smallWindFreqMul = 0.5f;
		const float largeWindFreqMul = 0.25f;

		const float smallWindTimeMul = 2.0f;
		const float largeWindTimeMul = 3.0f;

		const float smallWindWeight = 0.4f;
		const float largeWindWeight = 0.8f;

		const float smallWind = Simplex2D(grassPosition.xy * flowScale * smallWindFreqMul * windSpeed * smallWindTimeMul + g_flTime);
		const float largeWind = Simplex2D(grassPosition.xy * flowScale * largeWindFreqMul * windSpeed * largeWindTimeMul + g_flTime);

		return smallWind * smallWindWeight + largeWind * largeWindWeight;
	}

	PixelInput MainVs( VertexInput i )
    {
        GrassData grass = GrassInstanceData[i.nInstanceID];
        PixelInput o;

        float3 vertex = i.vPositionOs;
        const float maxBladeHeight = 28.3774f + 3.0f;
        float heightNorm = saturate(vertex.z / maxBladeHeight);

        float curve = sin(heightNorm * heightNorm * 3.14159 * 0.4f);
        float bendPower = 3.0f;
        vertex.y += curve * 5.0 * bendPower;

        float dist = distance(cameraPosition, grass.Position);
        if(dist > 1500)
        {
            float fat = saturate((dist - 1500.0) / (7000.0 - 1500.0));
            vertex.x *= lerp(1.0, 5.0, fat);
        }

        float cosR = cos(grass.Rotation);
        float sinR = sin(grass.Rotation);
        float3 rotatedVertex;
        rotatedVertex.x = vertex.x * cosR - vertex.y * sinR;
        rotatedVertex.y = vertex.x * sinR + vertex.y * cosR;
        rotatedVertex.z = vertex.z;

        float3 surfaceNormal = grass.Normal;
        float3 axis = abs(surfaceNormal.z) < 0.999 ? float3(0, 0, 1) : float3(0, 1, 0);
        float3 surfaceTangent = normalize(cross(axis, surfaceNormal));
        float3 surfaceBitangent = cross(surfaceNormal, surfaceTangent);
        
        float3 worldVertex = rotatedVertex.x * surfaceTangent + rotatedVertex.y * surfaceBitangent + rotatedVertex.z * surfaceNormal;

		// Should probably make this an attribute or get it from the noise. For now though I am going to leave it like this
        float3 windDirection = normalize(float3(1.0, 0, 1.0)); 
        
        float wind = CalculateWind(grass.Position);
        float tipInfluence = heightNorm * heightNorm; 
        
        const float windStrength = 5.0;
        
		float phase = Hash12(grass.Position.xz) * 1.28318;
		float gust = sin(g_flTime + phase) + cos(g_flTime + phase);


        worldVertex += windDirection * wind * gust * windStrength * tipInfluence + grass.Stiffness;

        float3 finalPosition = grass.Position + worldVertex;
        o.vPositionPs = Position3WsToPs( finalPosition );

        float randomVariation = Hash12(grass.Position.xz);
        o.vVertexColor = float4(randomVariation, tipInfluence, wind, dist);

        return o;
    }
}
PS
{
    #include "common/pixel.hlsl"
    
	RenderState(CullMode, NONE);

	float4 MainPs(PixelInput i) : SV_Target0
	{
		float3 grassColorDark  = float3(0.1, 0.3, 0.05);  // Dark green base
		float3 grassColorLight = float3(0.3, 0.6, 0.2);  // Light green variation
		float3 grassColorTip   = float3(0.5, 0.7, 0.3);  // Yellowish tips

		float variation = i.vVertexColor.r; 
		float height    = i.vVertexColor.g; 
		float noise     = i.vVertexColor.b;
		float distance  = i.vVertexColor.a;

		float lodTransitionStart = 500.0; 
		float lodTransitionEnd   = 7000.0; 
    
		float normalizedDist = saturate((distance - lodTransitionStart) / (lodTransitionEnd - lodTransitionStart));
		float ditheredDist = saturate(normalizedDist + (noise - 0.5) * 0.2);
    
		float blendMask = smoothstep(0.0, 1.0, ditheredDist);

		float random = frac(sin(variation * 12.9898) * 43758.5453);
		float3 baseGrass = lerp(grassColorDark, grassColorLight, variation);
    
		float yellowStrength = smoothstep(0.1, 0.8, random);
		float tipAmount = saturate(height * height) * yellowStrength;
		float noisyTip = tipAmount * lerp(0.1, 0.8, noise);
    
		float3 nearColor = lerp(baseGrass, grassColorTip, noisyTip + tipAmount);

		float3 averageBase = lerp(grassColorDark, grassColorLight, 0.7f);
		float3 farColor = lerp(averageBase, grassColorTip, 3.0f); 

		float3 finalColor = lerp(nearColor, farColor, blendMask);

		return float4(finalColor, 1.0);
	}
}