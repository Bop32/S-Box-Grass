FEATURES
{
    #include "common/features.hlsl"
}
MODES
{
    Forward();
    Depth( S_MODE_DEPTH );
}
COMMON
{
   #define CUSTOM_MATERIAL_INPUTS 

	#include "common/shared.hlsl"
	#include "procedural.hlsl"
	#include "common/classes/Depth.hlsl"
   	#include "Wind.hlsl"

   	struct GrassData
	{
		float3 Position;	
		float3 Normal;		
		float3 Color;
		float2  Rotation;
		float Stiffness;
		float  BendAmount;	
		float BladeHash;
		float DistanceFromCamera;
	};	

	StructuredBuffer<GrassData> GrassInstanceData < Attribute( "GrassData" ); >;
	
}
struct VertexInput
{
   float3 Position : POSITION < Semantic( PosXyz ); >;
	float Height : TEXCOORD0 < Semantic( LowPrecisionUv ); >;
	float4 ScreenPosition : SV_Position < Semantic( PosXyz ); >;
	uint nInstanceID : SV_InstanceID;
};
struct PixelInput
{
   float4 Position : SV_Position;
	float3 WorldPos : TEXCOORD0;
	float4 Normal : TEXCOORD1;
   uint nInstanceID : TEXCOORD2;
};

VS
{
	PixelInput MainVs( VertexInput i )
    {
        GrassData grass = GrassInstanceData[i.nInstanceID];
        PixelInput o;

        float3 vertex = i.Position;

        const float maxBladeHeight = 28.3774f + 3.0f;
        float heightNorm = saturate(vertex.z / maxBladeHeight);

        float tipInfluence = heightNorm * heightNorm; 
        float bladeHash = grass.BladeHash;

        float width = lerp(2.0, 1.0, heightNorm); 

        vertex.x *= width * 1.7f;
    
        float lodDistance = 1500 + bladeHash * 2000.0f;

        if(grass.DistanceFromCamera > lodDistance)
        {
            float fat = saturate((grass.DistanceFromCamera - lodDistance) / (10000.0 - lodDistance));
            vertex.x *= lerp(1.0, 5.0, fat);
            
            float3 cameraDirection = normalize(g_vCameraPositionWs - grass.Position);
    
            float3 right = float3(-cameraDirection.y, cameraDirection.x, 0);
            float3 up = float3(0, 0, 1);

			float3 rotatedVertex;
			rotatedVertex.x = vertex.x * grass.Rotation.x - vertex.y * grass.Rotation.y;
			rotatedVertex.y = vertex.x * grass.Rotation.y + vertex.y * grass.Rotation.x;
			rotatedVertex.z = vertex.z;
        
            float3 surfaceNormal = grass.Normal;
            float3 axis = abs(surfaceNormal.z) < 0.999 ? float3(0, 0, 1) : float3(0, 1, 0);
            float3 surfaceTangent = normalize(cross(axis, surfaceNormal));
            float3 surfaceBitangent = cross(surfaceNormal, surfaceTangent);
        
            float billboardFactor = smoothstep(50, 1000, grass.DistanceFromCamera);

            float3 finalTangent   = lerp(surfaceTangent, right, billboardFactor);
            float3 finalBitangent = lerp(surfaceBitangent, cameraDirection, billboardFactor);
            float3 finalNormal    = lerp(surfaceNormal, up, billboardFactor);

            o.WorldPos = grass.Position + rotatedVertex.x * finalTangent + rotatedVertex.y * finalBitangent + rotatedVertex.z * finalNormal;

			o.Position = Position3WsToPs( o.WorldPos );

			float baseAO = 1.0 - heightNorm; 
			o.Normal.xyz = normalize(lerp(rotatedVertex, surfaceNormal, 0.3));
			o.Normal.w = baseAO; 
			grass.Color = tipInfluence.xxx;
			
            //o.vVertexColor = float4(bladeHash, tipInfluence, tipInfluence, grass.DistanceFromCamera);
            return o;
        }

        float bendFalloff = pow(tipInfluence, 1.5); 
        vertex.y += bendFalloff * grass.BendAmount * 20;


        float3 rotatedVertex;
        rotatedVertex.x = vertex.x * grass.Rotation.x - vertex.y * grass.Rotation.y;
        rotatedVertex.y = vertex.x * grass.Rotation.y + vertex.y * grass.Rotation.x;
        rotatedVertex.z = vertex.z;

        float3 surfaceNormal = grass.Normal;
        float3 axis = abs(surfaceNormal.z) < 0.999 ? float3(0, 0, 1) : float3(0, 1, 0);
        float3 surfaceTangent = normalize(cross(axis, surfaceNormal));
        float3 surfaceBitangent = cross(surfaceNormal, surfaceTangent);

        // Hard coded for now 
        float3 windDirection = float3(1.0, 0.5f, 0.0);
    
        float wind = Wind::CalculateWind(grass.Position);
        float flexibility = 1.0 - grass.Stiffness;

        float angle = wind * flexibility * tipInfluence * 0.3f;

        float s = sin(angle);
        float c = cos(angle);

        float x = rotatedVertex.x;
        float z = rotatedVertex.z;

        rotatedVertex.x = x * c - z * s;
        rotatedVertex.z = x * s + z * c;

        float3 worldVertex = rotatedVertex.x * surfaceTangent + rotatedVertex.y * surfaceBitangent + rotatedVertex.z * surfaceNormal;

		o.WorldPos = grass.Position + worldVertex;
		o.Position = Position3WsToPs( o.WorldPos );

		float baseAO = 1.0 - heightNorm; 
        o.Normal.xyz = normalize(lerp(rotatedVertex, surfaceNormal, 0.3));
		o.Normal.w = baseAO; 
		grass.Color = tipInfluence.xxx;
        //o.vVertexColor = float4(bladeHash, tipInfluence, wind * tipInfluence * 1.25f, grass.DistanceFromCamera);
        //o.vVertexColor = float4(wind.xxx, 1);  // Used to see the noise 

        o.nInstanceID = i.nInstanceID;
        return o;
    }
}
PS
{
    #include "common/pixel.hlsl"
    
    RenderState(CullMode, NONE);

	float4 MainPs(PixelInput i) : SV_Target0
    {

		GrassData grass = GrassInstanceData[i.nInstanceID];

		Material m = Material::Init(i);

		m.Normal = i.Normal.xyz;
		m.WorldPosition = i.WorldPos;
		m.WorldPositionWithOffset = i.WorldPos + g_vCameraPositionWs;
		m.ScreenPosition = i.Position;
		m.AmbientOcclusion = 1.0 - (i.Normal.w);

		
        float3 grassColorDark  = float3(0.1, 0.3, 0.05);
        float3 grassColorLight = float3(0.3, 0.6, 0.2);
        float3 grassColorTip   = float3(0.5, 0.7, 0.3);

		float random = frac(sin(grass.BladeHash * 12.9898) * 43758.5453);
		 
		float3 baseCol = lerp(grassColorDark, grassColorLight, random);

		float height = grass.Color.x;
		float tipMask = grass.Color.x * grass.Color.x;
		float3 finalCol = lerp(baseCol, grassColorTip, tipMask);

		m.Albedo = finalCol;
		
		return ShadingModelStandard::Shade( m );
        /*
        // Patch color variants - adjust these to taste
        float3 grassColorDry    = float3(0.22, 0.40, 0.1);   
        float3 grassColorLush   = float3(0.05, 0.35, 0.08);  
        float3 grassColorPale   = float3(0.35, 0.55, 0.25);  

        float variation = i.vVertexColor.r; 
        float height    = i.vVertexColor.g; 
        float noise     = i.vVertexColor.b;
        float distance  = i.vVertexColor.a;

        float2 wp = i.vNormalWs.xy; 

        float2 patchCoordLarge  = wp * 0.0001f;  
        float2 patchCoordMedium = wp * 0.0005;   

        float patchLarge = Simplex2D(patchCoordLarge);

        float patchMedium = Simplex2D(patchCoordMedium);

        float patchValue = saturate(patchLarge * variation + patchMedium * variation);
        
        float lodTransitionStart = 1500.0; 
        float lodTransitionEnd   = 10000.0; 
        float normalizedDist = saturate((distance - lodTransitionStart) / (lodTransitionEnd - lodTransitionStart));
        float ditheredDist = saturate(normalizedDist + (noise - 0.5) * 0.25f);
        float blendMask = ditheredDist * ditheredDist * (3.0 - 2.0 * ditheredDist);

        float random = frac(sin(variation * 12.9898) * 43758.5453);
        float3 baseGrass = lerp(grassColorDark, grassColorLight, variation);

        float dryMask  = smoothstep(0.72, 0.80, patchValue);   
        float lushMask = smoothstep(0.28, 0.26, patchValue);   

        float3 patchedBase = baseGrass;
        patchedBase = lerp(patchedBase, grassColorDry,  dryMask  * 0.75);
        patchedBase = lerp(patchedBase, grassColorLush, lushMask * 0.6);

        float paleMask = smoothstep(0.55, 0.75, patchMedium) * (1.0 - dryMask);
        patchedBase = lerp(patchedBase, grassColorPale, paleMask * 0.2);

        float yellowStrength = smoothstep(0.2, 0.65, random);
        float tipAmount = saturate(height * height) * yellowStrength;
        float noisyTip = tipAmount * lerp(0.2, 0.90, noise);
        float3 nearColor = lerp(patchedBase, grassColorTip, noisyTip + tipAmount);

        float3 averageBase = lerp(grassColorDark, grassColorLight, 0.5f);
        float3 farColor = lerp(averageBase, grassColorTip, 0.2f);

        float3 finalColor = lerp(nearColor, farColor, blendMask);
        return float4(finalColor, 1.0);
        */
    }
}