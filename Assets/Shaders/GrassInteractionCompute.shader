MODES
{
    Default();
}

CS
{
#include "system.fxc"
#include "utilities.hlsl"

    // clang-format off
	RWTexture2D<float4> outputTexture < Attribute( "OutputInteractionTexture" ); >;

   float terrainSize < Attribute( "TerrainSize" ); >;
   float2 terrainPosition < Attribute( "TerrainPosition" ); >;
   float2 playerPosition < Attribute( "PlayerPosition" ); >;
   float2 textureSize < Attribute( "TextureSize" ); >;
   float radius < Attribute( "Radius" ); >;

    // clang-format on
    [numthreads(8, 8, 1)]
    void MainCs(uint3 id: SV_DispatchThreadID)
    {
        if (id.x >= textureSize.x || id.y >= textureSize.y)
            return;

        float2 center = (playerPosition - terrainPosition) / terrainSize * textureSize;

        float dist = length(id.xy - center);

        float4 current = outputTexture[id.xy];

        float t = saturate(dist / radius);
        float4 newColor = lerp(float4(1, 0, 0, 1), float4(0, 0, 0, 1), t);

        float decay = EaseInQuad(t);
        float4 currentColor = max(current, newColor) - float4(decay, 0, 0, 0);
        currentColor = max(currentColor, float4(0, 0, 0, 0));

        outputTexture[id.xy] = currentColor;
    }
}
