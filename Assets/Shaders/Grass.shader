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
        float3 Normal;
        float4 Color;
        float2 Rotation;
        float Height;
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
    float4 vNormalOs : NORMAL < Semantic( OptionallyCompressedTangentFrame ); >;
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
        bitangent = normalize(cross(surfaceNormal, tangent));
    }

    // Apply 2D yaw rotation (XY plane, Z-up)
    float3 ApplyYaw(float3 vertex, float2 rotation)
    {
        return float3(vertex.x * rotation.x - vertex.y * rotation.y, vertex.x * rotation.y + vertex.y * rotation.x, vertex.z);
    }

    // Transform local vector into world space
    float3 ToWorldSpace(float3 vertex, float3 tangent, float3 bitangent, float3 normal)
    {
        return vertex.x * tangent + vertex.y * bitangent + vertex.z * normal;
    }

    float3 BezierQuadratic(float3 P0, float3 P1, float3 P2, float t)
    {
        float u = 1.0 - t;

        return u * u * P0 + 2.0 * u * t * P1 + t * t * P2;
    }

    float3 BezierQuadraticDerivative(float3 P0, float3 P1, float3 P2, float t)
    {
        return 2.0 * (1.0 - t) * (P1 - P0) + 2.0 * t * (P2 - P1);
    }

    float3 BladeNormalFromTangent(float3 tangent)
    {
        float3 widthDir = float3(1, 0, 0);

        return normalize(cross(widthDir, normalize(tangent)));
    }

    PixelInput MainVs(VertexInput i)
    {
        GrassData grass = GrassInstanceData[i.nInstanceID];
        PixelInput o;
        o.nInstanceID = i.nInstanceID;

        float3 vertex = i.Position;

        float horizontalOffset = vertex.x - 0.5;

        float heightNorm = saturate(vertex.z / 28.3);

        float t = heightNorm;
        float3 P0 = float3(0, 0, 0);
        float3 P1 = float3(0, 0, 15);
        float3 P2 = float3(0, 28.3 * grass.BendAmount, grass.Height);
        float3 curve = BezierQuadratic(P0, P1, P2, t);

        vertex.y = curve.y;
        vertex.z = curve.z;

        vertex.x *= 1.5f;

        vertex = ApplyYaw(vertex, grass.Rotation);
        float3 surfaceNormal = grass.Normal;

        
        float3 surfaceTangent, surfaceBitangent;
        BuildSurfaceFrame(surfaceNormal, surfaceTangent, surfaceBitangent);
        
        if (grass.DistanceFromCamera > 1500 + grass.BladeHash * 1000)
        {
            vertex.x *= 5.0;
            float3 worldVertex = ToWorldSpace(vertex, surfaceTangent, surfaceBitangent, surfaceNormal);
            o.WorldPos = grass.Position + worldVertex;

            
            o.Position = Position3WsToPs(o.WorldPos);
            o.Normal.xyz = surfaceNormal;
            o.Normal.w = Wind::CalculateWind(grass.Position, grass.Height);
            o.Height = heightNorm;
            o.Side = i.Position.x;

            return o;
        }

        float3 tangent = normalize(BezierQuadraticDerivative(P0, P1, P2, t));
        tangent = ApplyYaw(tangent, grass.Rotation);

        float3 worldTangent = normalize(ToWorldSpace(tangent, surfaceTangent, surfaceBitangent, surfaceNormal));
        float3 localWidthDir = normalize(float3(grass.Rotation.x, grass.Rotation.y, 0));
        float3 worldWidthDir = normalize(cross(worldTangent, surfaceNormal));
        float3 worldNormal = normalize(cross(worldTangent, worldWidthDir));


        float wind = Wind::CalculateWind(grass.Position, grass.Height);
        float flexibility = 1.0 - grass.Stiffness;
        float angle = wind * flexibility * (heightNorm * heightNorm) * 0.2;
        float sinAngle = sin(angle), cosAngle = cos(angle);

        vertex.x = vertex.x * cosAngle - vertex.z * sinAngle;
        vertex.z = vertex.x * sinAngle + vertex.z * cosAngle;

        float3 worldVertex = ToWorldSpace(vertex, surfaceTangent, surfaceBitangent, surfaceNormal);

        o.WorldPos = grass.Position + worldVertex;

        float3 viewDirection = normalize(g_vCameraPositionWs - grass.Position);

        float edge = 1.0 - abs(dot(worldNormal, viewDirection));
        float edgeFactor = smoothstep(0.5, 1.0, edge);

        float3 cameraRightWs = normalize(Vector3VsToWs(float3(1, 0, 0)));

        o.WorldPos += cameraRightWs * horizontalOffset * edgeFactor * 2.0;

        o.Position = Position3WsToPs(o.WorldPos);

        o.Normal.xyz = worldNormal;
        o.Normal.w = wind;
        o.Height = heightNorm;
        o.Side = i.Position.x;

        return o;
    }
}

PS
{
#include "common/pixel.hlsl"

    RenderState(CullMode, NONE);

    float4 MainPs(PixelInput i, bool bIsFrontFace: SV_IsFrontFace) : SV_Target0
    {
        GrassData grass = GrassInstanceData[i.nInstanceID];

        float3 normal = i.Normal.xyz;

        if (bIsFrontFace)
            normal = -normal;

        // return float4(color, 1);
        // return float4(SrgbGammaToLinear(normal * 0.5 + 0.5), 1);

        float3 grassDark = float3(0.08, 0.25, 0.04);
        float3 grassLight = float3(0.25, 0.6, 0.12);
        float3 grassTip = float3(0.45, 0.55, 0.20);

        if (i.Side > 0)
        {
            grassDark *= 0.8;
            grassLight *= 0.8;
            grassTip *= 0.8;
        }

        float dryness = Hash01(grass.BladeHash + 999u) * 0.2;
        float3 dryColor = float3(0.4, 0.5, 0.1);

        float random = frac(sin(grass.BladeHash * 12.9898) * 43758.5453);
        float3 baseColor = lerp(grassDark, grassLight, random + i.Normal.w * 0.2 + 0.5);
        baseColor = lerp(baseColor, dryColor, dryness * i.Height);
        float3 Albedo = lerp(baseColor, grassTip, i.Height * i.Height * random);

        Light sun = Light::From(i.Position.xyz, float4(i.WorldPos, 1), 0);

        float3 L = normalize(sun.Direction);
        float3 N = normal;
        float NdotL = saturate(dot(N, L));

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
        float3 translucency = Albedo * sun.Color * pow(transDot, 6.0) * 0.15 * i.Height;

        float ao = lerp(0.3, 1.0, i.Height);
        float3 finalLight = (Albedo * diffuse * sun.Color + ambient) * ao + translucency;
        return float4(finalLight, 1.0);
    }
}
