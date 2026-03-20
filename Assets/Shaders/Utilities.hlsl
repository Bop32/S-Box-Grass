#ifndef UTILITIES_HLSL
#define UTILITIES_HLSL

uint Hash(uint n)
{
    n ^= n >> 16;
    n *= 0x7feb352d;
    n ^= n >> 15;
    n *= 0x846ca68b;
    n ^= n >> 16;
    return n;
}

float Hash01(uint n)
{
    return (Hash(n) & 0x00FFFFFFu) / 16777215.0;
}

float2 Hash02(uint n)
{
    uint h = Hash(n);   
    return float2((h & 0xFFFFu), (h >> 16)) / 65535.0;
}


float Random(uint seed, float minVal, float maxVal)
{
    return minVal + Hash01(seed) * (maxVal - minVal);
}

float2 Random2(uint seed, float minVal, float maxVal)
{
    return float2(minVal + Hash01(seed) * (maxVal - minVal), minVal + Hash01(seed + 1u) * (maxVal - minVal));
}

float EaseInQuad(float t)
{
    return t * t;
}

float EaseInCubic(float t)
{
    return t * t * t;
}

float EaseOutElastic(float t)
{
    float c4 = (2.0 * 3.14159) / 3.0;
    return t == 0.0 ? 0.0 : t == 1.0 ? 1.0 : pow(2.0, -10.0 * t) * sin((t * 10.0 - 0.75) * c4) + 1.0;
}

#endif 