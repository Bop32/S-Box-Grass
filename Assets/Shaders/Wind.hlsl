#ifndef WIND_HLSL
#define WIND_HLSL

#include "common/Bindless.hlsl"
#include "procedural.hlsl"


#define WindTime g_flTime

class Wind
{
    static float CalculateWind(float3 grassPosition)
    {
        const float flowScale = 0.02f; // Controls size of wind patterns || Lower = bigger, and smoother waves

        struct Wind
        {
            float Frequency;
            float Speed;
            float Weight;
        };

        Wind gust = { 0.5f, 1.2f, 0.3f };    // Quick, subtle ripples
        Wind primary = { 0.2f, 0.6f, 0.7f }; // Main movement
        Wind large = { 0.08f, 0.4f, 1.0f };  // Slow, strong swaying

        float gustWind = Simplex2D(grassPosition.xy * flowScale * gust.Frequency + WindTime * gust.Speed);
        float primaryWind = Simplex2D(grassPosition.xy * flowScale * primary.Frequency + WindTime * primary.Speed);
        float largeWind = Simplex2D(grassPosition.xy * flowScale * large.Frequency + WindTime * large.Speed);

        float combinedWind = gustWind * gust.Weight + primaryWind * primary.Weight + largeWind * large.Weight;

        return combinedWind;
    }
};

#endif 