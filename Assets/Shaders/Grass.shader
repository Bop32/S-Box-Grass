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
		float  BendAmount;	
		float  Noise;        
		bool   ShouldDiscard;
	};	

	StructuredBuffer<GrassData> GrassInstanceData < Attribute( "GrassData" ); >;

	float Hash12(float2 p)
	{
		float3 p3 = frac(float3(p.xyx) * 0.1031);
		p3 += dot(p3, p3.yzx + 33.33);
		return frac((p3.x + p3.y) * p3.z);
	}


	PixelInput MainVs( VertexInput i )
	{
		GrassData grass = GrassInstanceData[i.nInstanceID];
			
		PixelInput o;

		float cosR = cos(grass.Rotation);
		float sinR = sin(grass.Rotation);
		float3 vertex = i.vPositionOs;
		
		float heightFactor = vertex.z * vertex.z;
		float totalBend = heightFactor * grass.BendAmount;
		vertex.y += totalBend;
		vertex.z -= totalBend * 0.10f;
		//vertex.x *= fade;
		
		float windSpeed = 0.1f;
		float windStrength = 1.50f;
		float flowScale = 0.05f;

		float maxHeight = 10.0;
		float tipInfluence = saturate(vertex.z / maxHeight);
		tipInfluence = tipInfluence * tipInfluence; 

		float3 vPositionWs = grass.Position.xyz;
	
		float stripedNoise = Simplex2D(vPositionWs.xy * flowScale * windSpeed + g_flTime);

		float flowDirection = stripedNoise;
	
		vertex.x += flowDirection * windStrength * tipInfluence;
		vertex.y += flowDirection * windStrength * tipInfluence;

		float3 rotatedVertex;
		rotatedVertex.x = vertex.x * cosR - vertex.y * sinR;
		rotatedVertex.y = vertex.x * sinR + vertex.y * cosR;
		rotatedVertex.z = vertex.z;
	
		float3 surfaceNormal = grass.Normal;
		float3 axis = abs(surfaceNormal.z) < 0.999 ? float3(0, 0, 1) : float3(0, 1, 0);

		float3 surfaceTangent = normalize(cross(axis, surfaceNormal));
		float3 surfaceBitangent = cross(surfaceNormal, surfaceTangent);

		float3 worldVertex = rotatedVertex.x * surfaceTangent + rotatedVertex.y * surfaceBitangent + rotatedVertex.z * surfaceNormal;

		float3 finalPosition = grass.Position + worldVertex;
	
		o.vPositionPs = Position3WsToPs( finalPosition );
	
		float randomVariation = Hash12(grass.Position.xz);
	
		//o.vVertexColor = float4(stripedNoise, stripedNoise, stripedNoise, 1);
		o.vVertexColor = float4(randomVariation, tipInfluence, stripedNoise, 1);

		return o;
	}
}
PS
{
    #include "common/pixel.hlsl"
    
	RenderState(CullMode, NONE);

	float4 MainPs( PixelInput i ) : SV_Target0
	{
 		float3 grassColorDark = float3(0.1, 0.3, 0.05);   // Dark green
		float3 grassColorLight = float3(0.3, 0.6, 0.2);   // Light green
		float3 grassColorTip = float3(0.5, 0.7, 0.3);     // Yellow ish
	
		float variation = i.vVertexColor.r; 
		float height = i.vVertexColor.g; 
		float noise = i.vVertexColor.b;
	
		float3 grassColor = lerp(grassColorDark, grassColorLight, variation);

		float random = frac(sin(variation * 12.9898) * 43758.5453);
		
		float yellowStrength = smoothstep(0.1f, 0.8f, random);

		float tipAmount = saturate(height * height) * yellowStrength;

		grassColor = lerp(grassColor, grassColorTip, tipAmount);
	
		float noisyTip = tipAmount * lerp(0.1f, 1.0f, noise);
		grassColor = lerp(grassColor, grassColorTip, noisyTip);

		return float4(grassColor, 1);
	}
}