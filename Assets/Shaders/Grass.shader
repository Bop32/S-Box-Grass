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
	#include "common/shared.hlsl"
   #define CUSTOM_MATERIAL_INPUTS 

   struct GrassData
	{
		float3 Position;
      float3 Normal;
      float3 Wind;
      float2 ClumpFacing;
      float2 Facing;
      float3 Color;
      uint Hash;
      float Height;
      float Width;
      float Tilt;
      float Bend;
      float SideCurve;
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
   float3 BezierCurve(float3 p0, float3 p1, float3 p2, float t) 
   {
		float u = 1.0 - t;
		return u * u * p0 + 2.0 * u * t * p1 + t * t * p2;
	}

   float3 GhostOfTsushimaBladeDeform(float3 basePos, GrassData grass, float heightT)
	{
		// Base position starts at the blade root
		float3 pos = grass.Position;
		
		// Apply width scaling to base position (for quad vertices)
		basePos.x *= grass.Width * 0.5; // Scale width
		
		// Create blade-local coordinate system
		float3 forward = normalize(float3(grass.Facing.x, grass.Facing.y, 0));
		float3 right = float3(-grass.Facing.y, grass.Facing.x, 0);
		float3 up = float3(0, 0, 1);
      
		// Apply facing rotation to base position
		float3 rotatedBase = basePos.x * right + basePos.y * forward + basePos.z * up;
		
		// Ghost of Tsushima curve calculation
		// Uses quadratic ease-out for natural blade curvature
		float curve = heightT * heightT * (3.0 - 2.0 * heightT); // Smooth step
		float heightScale = heightT * grass.Height;
		
		// Natural blade tilt (from wind and growth patterns)
		float tiltAmount = grass.Tilt * (3.14159 / 180.0); // Convert to radians
		float3 tiltDirection = forward * sin(tiltAmount) + up * (cos(tiltAmount) - 1.0);
		
		// Side curve for blade character variation
		float sideCurveAmount = grass.SideCurve * curve; // More curve at the top
		float3 sideOffset = right * sideCurveAmount * grass.Height * 0.3;
		
		// Wind deformation with proper physics-based bending
		// Wind effect increases quadratically with height (like a cantilever beam)
		float windStrength = curve * curve;
		float3 windDeform = grass.Wind * windStrength * grass.Bend;
		
		// Clump coherence - blades in the same clump bend similarly
		float clumpInfluence = 0.6; // How much clumps affect individual blades
		float2 clumpWindDir = normalize(grass.ClumpFacing);
		float clumpWindAmount = dot(normalize(grass.Wind.xy), clumpWindDir);
		float3 clumpDeform = float3(clumpWindDir * clumpWindAmount * windStrength * 0.5, 0);
		windDeform = lerp(windDeform, windDeform + clumpDeform, clumpInfluence);
		
		// Combine all deformations
		float3 finalPos = pos + rotatedBase;
		finalPos.z += heightScale; // Apply height
		finalPos += tiltDirection * heightScale * 0.4; // Apply tilt
		finalPos += sideOffset; // Apply side curve
		finalPos += windDeform; // Apply wind
		
		// Prevent grass from going underground due to extreme bending
		finalPos.z = max(finalPos.z, pos.z);
		
		return finalPos;
	}

	PixelInput MainVs( VertexInput i )
    {
        GrassData grass = GrassInstanceData[i.nInstanceID];
        PixelInput o;

        const float maxBladeHeight = 28.3774f;
      
        const float heightT = saturate(i.Position.z / maxBladeHeight);
         o.WorldPos = GhostOfTsushimaBladeDeform(i.Position, grass, heightT);
         o.Position = Position3WsToPs( o.WorldPos );

        float2 facing = grass.Facing;

        o.Normal.xyz = float3(facing.x, 0, facing.y);
         float baseAO = 1.0 - heightT; // More AO at base
		   float widthAO = saturate(grass.Width * 0.5); // Wider blades cast more shadow
		   o.Normal.w = baseAO * widthAO;

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

         Material m = Material::Init();

         m.WorldPosition = i.WorldPos;
         m.WorldPositionWithOffset = i.WorldPos + g_vCameraPositionWs;
         m.ScreenPosition = i.Position;
         m.Normal = i.Normal.xyz;
         m.AmbientOcclusion = i.Normal.w * i.Normal.w;

		   m.Albedo = float3(0.1, 0.6, 0.1);
        
         return ShadingModelStandard::Shade( m );
   }
}