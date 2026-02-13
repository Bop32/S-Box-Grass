FEATURES
{
    #include "common/features.hlsl"
}
MODES
{
    Forward();
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
		float BladeHash;
		float DistanceFromCamera;
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
        const float flowScale = 0.02f;       // Controls size of wind patterns || Lower = bigger, and smoother waves

        struct Wind
        {
            float Frequency;
            float Speed;
            float Weight;
        };
    
        Wind gust    = { 0.5f, 1.2f, 0.3f };  // Quick, subtle ripples
        Wind primary = { 0.2f, 0.6f, 0.7f };  // Main movement
        Wind large   = { 0.05f, 0.5f, 0.5f }; // Slow, strong swaying
    
        float gustWind    = Simplex2D(grassPosition.xy * flowScale * gust.Frequency + g_flTime * gust.Speed);
        float primaryWind = Simplex2D(grassPosition.xy * flowScale * primary.Frequency + g_flTime * primary.Speed);
        float largeWind   = Simplex2D(grassPosition.xy * flowScale * large.Frequency + g_flTime * large.Speed);

        float combinedWind = gustWind * gust.Weight + primaryWind * primary.Weight + largeWind * large.Weight;

        return combinedWind;
    }

	PixelInput MainVs( VertexInput i )
    {
        GrassData grass = GrassInstanceData[i.nInstanceID];
        PixelInput o;

        float3 vertex = i.vPositionOs;

        const float maxBladeHeight = 28.3774f + 3.0f;
        float heightNorm = saturate(vertex.z / maxBladeHeight);

        float tipInfluence = heightNorm * heightNorm; 
        float randomVariation = grass.BladeHash;

        float width = lerp(3.0, 1.0, heightNorm); 

        vertex.x *= width * 1.7f;

        float randID = grass.BladeHash;
    
        float lodDistance = 1500 + randID * 2500.0f;

        if(grass.DistanceFromCamera > lodDistance)
        {
            float fat = saturate((grass.DistanceFromCamera - lodDistance) / (10000.0 - lodDistance));
            vertex.x *= lerp(1.0, 10.0, fat);
            
            float cosR = cos(grass.Rotation);
            float sinR = sin(grass.Rotation);
        
            float3 cameraDirection = normalize(cameraPosition - grass.Position);
    
            float3 right = float3(-cameraDirection.y, cameraDirection.x, 0);
            float3 up = float3(0, 0, 1);

            float3 rotatedVertex;
            rotatedVertex.x = vertex.x * cosR - vertex.y * sinR;
            rotatedVertex.y = vertex.x * sinR + vertex.y * cosR;
            rotatedVertex.z = vertex.z;
        
            float3 surfaceNormal = grass.Normal;
            float3 axis = abs(surfaceNormal.z) < 0.999 ? float3(0, 0, 1) : float3(0, 1, 0);
            float3 surfaceTangent = normalize(cross(axis, surfaceNormal));
            float3 surfaceBitangent = cross(surfaceNormal, surfaceTangent);
        
            float billboardFactor = smoothstep(1500, 10000, grass.DistanceFromCamera);

            float3 finalTangent   = lerp(surfaceTangent, right, billboardFactor);
            float3 finalBitangent = lerp(surfaceBitangent, toCamera, billboardFactor);
            float3 finalNormal    = lerp(surfaceNormal, up, billboardFactor);

            float3 worldVertex = rotatedVertex.x * finalTangent + rotatedVertex.y * finalBitangent + rotatedVertex.z * finalNormal;

            o.vPositionPs = Position3WsToPs( grass.Position + worldVertex );
            o.vVertexColor = float4(randomVariation, tipInfluence, tipInfluence, grass.DistanceFromCamera);
            return o;
        }

        float curve = sin(heightNorm * heightNorm * 3.14159 * 0.4f);
        float bendPower = 3.0f;
        vertex.y += curve * 5.0 * bendPower;  

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

        // Hard coded for now 
        float3 windDirection = float3(1.0, 0.5f, 0.0);
    
        float wind = CalculateWind(grass.Position);
        const float windStrength = 10.0;
    
        float flexibility = 1.0 - grass.Stiffness;
        worldVertex += windDirection * wind * windStrength * tipInfluence * flexibility;

        float3 finalPosition = grass.Position + worldVertex;
        o.vPositionPs = Position3WsToPs( finalPosition );

        o.vVertexColor = float4(randomVariation, tipInfluence, wind * tipInfluence * 1.25f, grass.DistanceFromCamera);
        //o.vVertexColor = float4(wind.xxx, 1);  // Used to see the noise 

        return o;
    }
}
PS
{
    #include "common/pixel.hlsl"
    
    RenderState(CullMode, NONE);

	float4 MainPs(PixelInput i) : SV_Target0
    {
	    float3 grassColorDark  = float3(0.1, 0.3, 0.05);
	    float3 grassColorLight = float3(0.3, 0.6, 0.2);
	    float3 grassColorTip   = float3(0.5, 0.7, 0.3);
	
	    float variation = i.vVertexColor.r; 
	    float height    = i.vVertexColor.g; 
	    float noise     = i.vVertexColor.b;
	    float distance  = i.vVertexColor.a;
	
	    float lodTransitionStart = 1500.0; 
	    float lodTransitionEnd   = 10000.0; 
	
	    float normalizedDist = saturate((distance - lodTransitionStart) / (lodTransitionEnd - lodTransitionStart));
	
	    float ditheredDist = saturate(normalizedDist + (noise - 0.5) * 0.25f);
	
	    float blendMask = ditheredDist * ditheredDist * (3.0 - 2.0 * ditheredDist);
	
	    float random = frac(sin(variation * 12.9898) * 43758.5453);
	    float3 baseGrass = lerp(grassColorDark, grassColorLight, variation);
	
	    float yellowStrength = smoothstep(0.1, 0.8, random);
	    float tipAmount = saturate(height * height) * yellowStrength;
	    float noisyTip = tipAmount * lerp(0.1, 0.90, noise);
	
	    float3 nearColor = lerp(baseGrass, grassColorTip, noisyTip + tipAmount);
	
	    float3 averageBase = lerp(grassColorDark, grassColorLight, 0.5f);
	    float3 farColor = lerp(averageBase, grassColorTip, 0.2f);
	
	    float3 finalColor = lerp(nearColor, farColor, blendMask);
	
	    return float4(finalColor, 1.0);
    }
}