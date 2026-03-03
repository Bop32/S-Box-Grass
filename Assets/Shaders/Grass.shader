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
    // clang-format off
      #define CUSTOM_MATERIAL_INPUTS

      #include "common/shared.hlsl"
      #include "common/classes/Depth.hlsl"
      #include "Wind.hlsl"
      #include "procedural.hlsl"
      #include "utilities.hlsl"


    struct GrassData
    {
        float3 Position;
        float _pad0;
        float3 Normal;
        float _pad1;
        float4 Color;
        float2 Rotation;
        float Stiffness;
        float BendAmount;
        float BladeHash;
        float DistanceFromCamera;
    };

    StructuredBuffer<GrassData> GrassInstanceData < Attribute("GrassData");> ;
}

struct VertexInput
{
    float3 Position : POSITION < Semantic(PosXyz); > ;
    float2 TexCoord1 : TEXCOORD0 < Semantic(LowPrecisionUv); > ;
    float4 ScreenPosition : SV_Position < Semantic(PosXyz); > ;
    uint nInstanceID : SV_InstanceID;
};

struct PixelInput
{
    float4 Position : SV_Position;
    float3 WorldPos : TEXCOORD0;
    float4 Normal : TEXCOORD1; // xyz = world normal, w = ao
    uint nInstanceID : TEXCOORD2;
    float Height : TEXCOORD3;
    float Side : TEXCOORD4;
};

// clang-format on
VS
{
    // Build tangent/bitangent frame from a surface normal (Z-up)
    void BuildSurfaceFrame(float3 surfaceNormal, out float3 tangent, out float3 bitangent)
    {
        float3 axis = abs(surfaceNormal.z) < 0.999 ? float3(0, 0, 1) : float3(0, 1, 0);
        tangent = normalize(cross(axis, surfaceNormal));
        bitangent = cross(surfaceNormal, tangent);
    }

    // Apply 2D yaw rotation (XY plane, Z-up)
    float3 ApplyYaw(float3 vertex, float2 rotation)
    {
        return float3(vertex.x * rotation.x - vertex.y * rotation.y, vertex.x * rotation.y + vertex.y * rotation.x, vertex.z);
    }

    // Transform local vector into world space via surface frame
    float3 ToWorldSpace(float3 vertex, float3 tangent, float3 bitangent, float3 normal)
    {
        return vertex.x * tangent + vertex.y * bitangent + vertex.z * normal;
    }

    PixelInput MainVs(VertexInput i)
    {
        GrassData grass = GrassInstanceData[i.nInstanceID];
        PixelInput o;
        o.nInstanceID = i.nInstanceID;

        float3 vertex = i.Position;
        float heightNorm = 1.0 - i.TexCoord1.y;
        float tipInfluence = heightNorm * heightNorm;
        float width = lerp(2.0, 1.0, heightNorm);

        vertex.x *= width;

        float3 surfaceNormal = grass.Normal;
        float3 surfaceTangent, surfaceBitangent;
        BuildSurfaceFrame(surfaceNormal, surfaceTangent, surfaceBitangent);

        float lodDistance = 1500.0 + grass.BladeHash * 1500.0;
        if (grass.DistanceFromCamera > lodDistance)
        {
            float fat = saturate((grass.DistanceFromCamera - lodDistance) / (10000.0 - lodDistance));
            vertex.x *= lerp(1.0, 2.0, fat);

            float3 camDir = normalize(g_vCameraPositionWs - grass.Position);
            float3 up = float3(0, 0, 1);
            float3 right = float3(-camDir.y, camDir.x, 0);

            float3 rotVert = ApplyYaw(vertex, grass.Rotation);

            float billboard = smoothstep(50, 1000, grass.DistanceFromCamera);
            float3 fTangent = lerp(surfaceTangent, right, billboard);
            float3 fBitangent = lerp(surfaceBitangent, camDir, billboard);
            float3 fNormal = lerp(surfaceNormal, up, billboard);

            o.WorldPos = grass.Position + ToWorldSpace(rotVert, fTangent, fBitangent, fNormal);
            o.Position = Position3WsToPs(o.WorldPos);
            o.Normal.xyz = normalize(lerp(rotVert, surfaceNormal, 0.3));
            o.Normal.w = heightNorm * width;
            o.Height = heightNorm;
            o.Side = 0;
            return o;
        }

        // Random height variation per blade, not sure if I will keep this
        vertex.z *= lerp(0.4, 1.0, grass.BladeHash);

        const float bendStrength = 20.0;
        float bendFalloff = pow(tipInfluence, 1.5);
        vertex.y += bendFalloff * grass.BendAmount * bendStrength;

        // Curve normal (derivative of bend curve)
        float dBend = 1.5 * pow(tipInfluence, 0.5) * grass.BendAmount * bendStrength;
        float3 localNormal = normalize(float3(0, -1, dBend));

        float3 rotVertex = ApplyYaw(vertex, grass.Rotation);
        float3 rotNormal = ApplyYaw(localNormal, grass.Rotation);

        float wind = Wind::CalculateWind(grass.Position);
        float flexibility = 1.0 - grass.Stiffness;
        float angle = wind * flexibility * tipInfluence * 0.3;
        float sinAngle = sin(angle), cosAngle = cos(angle);

        // Wind rotation in XZ plane (Z-up)
        rotVertex.x = rotVertex.x * cosAngle - rotVertex.z * sinAngle;
        rotVertex.z = rotVertex.x * sinAngle + rotVertex.z * cosAngle;
        rotNormal.x = rotNormal.x * cosAngle - rotNormal.z * sinAngle;
        rotNormal.z = rotNormal.x * sinAngle + rotNormal.z * cosAngle;

        o.WorldPos = grass.Position + ToWorldSpace(rotVertex, surfaceTangent, surfaceBitangent, surfaceNormal);
        float3 worldNormal = normalize(ToWorldSpace(rotNormal, surfaceTangent, surfaceBitangent, surfaceNormal));

        // My attempt at View-independent thickening. Works but not great.
        float3 localFaceNormal = float3(0, 1, 0);
        float3 bladeFaceNormal = normalize(ToWorldSpace(ApplyYaw(localFaceNormal, grass.Rotation), surfaceTangent, surfaceBitangent, surfaceNormal));
        float3 dirToCam = normalize(g_vCameraPositionWs - grass.Position);
        float3 camRight = float3(g_matWorldToView[0][0], g_matWorldToView[1][0], g_matWorldToView[2][0]);
        float edgeFactor = 1.0 - abs(dot(bladeFaceNormal, dirToCam));

        o.WorldPos += camRight * i.Position.x * edgeFactor * 1.5;

        o.Position = Position3WsToPs(o.WorldPos);
        o.Normal.xyz = worldNormal;
        o.Normal.w = heightNorm * width;
        o.Height = heightNorm;
        o.Side = i.Position.x;
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

        float3 grassDark = float3(0.1, 0.3, 0.05);
        float3 grassLight = float3(0.3, 0.6, 0.2);
        float3 grassTip = float3(0.5, 0.7, 0.3);


        if(i.Side > 0)
        {
            grassDark *= 0.8;
            grassLight *= 0.8;
            grassTip *= 0.8;
        }

        float random = frac(sin(grass.BladeHash * 12.9898) * 43758.5453);
        float3 baseColor = lerp(grassDark, grassLight, random);
        float3 Albedo = lerp(baseColor, grassTip, i.Height * i.Height);

        // No idea what is happening below but it looks good but since shading was expensive we can just fake lighting.
        Light sun = Light::From(i.WorldPos, 0, 0);
        float3 L = normalize(sun.Direction);
        float3 N = i.Normal.xyz;

        float NdotL = dot(N, L);
        float wrap = 0.3;
        float backface = saturate(-NdotL * 0.5 + 0.5);
        float diffuse = saturate((NdotL + wrap) / (1.0 + wrap));
        diffuse = max(diffuse, backface * 0.3);

        float3 skyColor = float3(0.1, 0.3, 0.5);
        float3 groundColor = float3(0.1, 0.15, 0.05);
        float hemi = dot(N, float3(0, 0, 1)) * 0.5 + 0.5;
        float3 ambient = lerp(groundColor, skyColor, hemi) * Albedo * sun.Color;

        float3 viewDir = normalize(g_vCameraPositionWs - i.WorldPos);
        float3 transDir = normalize(L + N * 0.3);
        float transDot = saturate(dot(viewDir, -transDir));
        float3 translucency = Albedo * sun.Color * pow(transDot, 4.0) * 0.4 * i.Height;

        float ao = lerp(0.3, 1.0, i.Normal.w);

        float3 finalLight = (Albedo * diffuse * sun.Color + ambient) * ao + translucency;
        return float4(finalLight, 1.0);
    }
}
