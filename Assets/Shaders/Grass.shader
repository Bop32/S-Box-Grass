FEATURES
{
#include "common/features.hlsl"
}
MODES
{
    Forward();
    Depth(S_MODE_DEPTH);
}
COMMON
{
#define CUSTOM_MATERIAL_INPUTS

    // clang-format off
#include "common/shared.hlsl"
#include "common/classes/Depth.hlsl"
#include "Wind.hlsl"
#include "procedural.hlsl"

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

    StructuredBuffer<GrassData> GrassInstanceData < Attribute( "GrassData" ); >;
	
}
struct VertexInput
{
   float3 Position : POSITION < Semantic( PosXyz ); >;
	float Height : TEXCOORD0 < Semantic( LowPrecisionUv ); >;
   float2 TexCoord1 : TEXCOORD1 < Semantic( LowPrecisionUv ); >;  // add this
	float4 ScreenPosition : SV_Position < Semantic( PosXyz ); >;
	uint nInstanceID : SV_InstanceID;
};

// clang-format on
struct PixelInput
{
    float4 Position : SV_Position;
    float3 WorldPos : TEXCOORD0;
    float4 Normal : TEXCOORD1;
    uint nInstanceID : TEXCOORD2;
    float Height : TEXCOORD3;
};

VS
{
    float easeOut(float x, float power)
    {
        return 1.0 - pow(1.0 - saturate(x), power);
    }

    PixelInput MainVs(VertexInput i)
    {
        GrassData grass = GrassInstanceData[i.nInstanceID];
        PixelInput o;
        o.Position = 0;

        if (grass.DistanceFromCamera < 0)
            return o;

        float3 vertex = i.Position;

        const float maxBladeHeight = 28.3774f + 3.0f;
        float heightNorm = saturate(vertex.z / maxBladeHeight);

        float tipInfluence = heightNorm * heightNorm;
        float bladeHash = grass.BladeHash;

        float width = lerp(2.0, 1.0, heightNorm);

        vertex.x *= width;

        float lodDistance = 1500 + bladeHash * 2000.0f;

        if (grass.DistanceFromCamera > lodDistance)
        {
            float fat = saturate((grass.DistanceFromCamera - lodDistance) / (10000.0 - lodDistance));
            vertex.x *= lerp(1.0, 2.0, fat);

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

            float3 finalTangent = lerp(surfaceTangent, right, billboardFactor);
            float3 finalBitangent = lerp(surfaceBitangent, cameraDirection, billboardFactor);
            float3 finalNormal = lerp(surfaceNormal, up, billboardFactor);

            o.WorldPos = grass.Position + rotatedVertex.x * finalTangent + rotatedVertex.y * finalBitangent + rotatedVertex.z * finalNormal;

            o.Position = Position3WsToPs(o.WorldPos);

            float baseAO = heightNorm;
            o.Normal.xyz = normalize(lerp(rotatedVertex, surfaceNormal, 0.3));
            o.Normal.w = baseAO * width;
            grass.Color = float4(vertex.z, tipInfluence, tipInfluence, 1);

            o.Height = heightNorm;
            // o.vVertexColor = float4(bladeHash, tipInfluence, tipInfluence, grass.DistanceFromCamera);
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

        float3 localNormal = float3(0, 0, 1);

        // Yaw rotation (already in XY plane, correct for Z-up)
        float3 rotatedNormal;
        rotatedNormal.x = localNormal.x * grass.Rotation.x - localNormal.y * grass.Rotation.y;
        rotatedNormal.y = localNormal.x * grass.Rotation.y + localNormal.y * grass.Rotation.x;
        rotatedNormal.z = localNormal.z;

        float nx = rotatedNormal.x;
        float nz = rotatedNormal.z;
        rotatedNormal.x = nx * c - nz * s;
        rotatedNormal.z = nx * s + nz * c;

        float3 worldNormal = normalize(rotatedNormal.x * surfaceTangent + rotatedNormal.y * surfaceBitangent + rotatedNormal.z * surfaceNormal);

        o.Position = Position3WsToPs(o.WorldPos);

        o.Normal.xyz = normalize(lerp(worldNormal, surfaceNormal, 0.01));

        o.Normal.w = heightNorm * width;
        grass.Color = float4(abs(vertex.x), abs(vertex.y), abs(vertex.z) , 1);
        o.Height = heightNorm;
        // o.vVertexColor = float4(bladeHash, tipInfluence, wind * tipInfluence * 1.25f, grass.DistanceFromCamera);
        // o.vVertexColor = float4(wind.xxx, 1);  // Used to see the noise

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

        float3 grassColorDark = float3(0.1, 0.3, 0.05);
        float3 grassColorLight = float3(0.3, 0.6, 0.2);
        float3 grassColorTip = float3(0.5, 0.7, 0.3);

        float random = frac(sin(grass.BladeHash * 12.9898) * 43758.5453);

        float3 baseCol = lerp(grassColorDark, grassColorLight, random);

        float3 finalColor = lerp(baseCol, grassColorTip, i.Height * i.Height);

        float3 Albedo = finalColor;

        Light sun = Light::From(i.WorldPos, 0, 0);
        float3 L = normalize(sun.Direction);

        // Wrapped diffuse - softer transition between lit and unlit
        float NdotL = dot(i.Normal.xyz, L);
        float wrap = 0.15; // was 0.5, much more subtle
        float wrappedDiffuse = saturate((NdotL + wrap) / (1.0 + wrap));

        // Hemisphere ambient - sky color from above, ground bounce from below
        float3 skyColor = float3(0.1, 0.3, 0.5);
        float3 groundColor = float3(0.1, 0.15, 0.05);
        float hemisphereT = dot(i.Normal.xyz, float3(0, 1, 0)) * 0.5 + 0.5;
        float3 ambient = lerp(groundColor, skyColor, hemisphereT) * Albedo;

        // Translucency - sun punching through the blade
        float3 viewDirection = normalize(g_vCameraPositionWs - i.WorldPos);
        float3 translucentDir = normalize(L + i.Normal.xyz * 0.3);
        float translucentDot = saturate(dot(viewDirection, -translucentDir));
        float translucency = pow(translucentDot, 4.0) * 0.4 * i.Height; // stronger at tip
        float3 translucentColor = Albedo * sun.Color * translucency;

        // AO from your existing baseAO stored in Normal.w
        float ao = i.Normal.w;

        float3 finalLight = (Albedo * wrappedDiffuse * sun.Color + ambient) * ao + translucentColor;
        return float4(finalLight, 1.0);

        // return ShadingModelStandard::Shade(m);
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
