﻿Shader "FaceAndObjectDetect/cartToPolar"
{

    Properties
    {
        _TexCam ("L1 Camera", 2D) = "black" {}
        _TexBuff ("cartToPolar Buffer", 2D) = "black" {}
        _Dst ("Distance Clip", Float) = 0.05
    }

    SubShader
    {
        Tags { "Queue"="Overlay+1" "ForceNoShadowCasting"="True" "IgnoreProjector"="True" }
        ZWrite Off
        ZTest Always
        Cull Front

        Pass
        {
            Lighting Off
            SeparateSpecular Off
            Fog { Mode Off }

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma fragmentoption ARB_precision_hint_fastest
            #pragma target 5.0

            #include "UnityCG.cginc"

            #define outRes _TexBuff_TexelSize.zw
            RWStructuredBuffer<float4> buffer : register(u1);

            Texture2D<float4> _TexCam;
            Texture2D<float4> _TexBuff;
            float4 _TexBuff_TexelSize;
            float _Dst;

            static const float3x3 fX = {
                -1, 0, 1,
                -2, 0, 2,
                -1, 0, 1
            };

            static const float3x3 fY = {
                -1, -2, -1,
                 0,  0,  0,
                 1,  2,  1
            };

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float3 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = fixed4(v.uv * 2 - 1, 0, 1);
                #ifdef UNITY_UV_STARTS_AT_TOP
                v.uv.y = 1-v.uv.y;
                #endif
                o.uv.xy = UnityStereoTransformScreenSpaceTex(v.uv);
                o.uv.z = (distance(_WorldSpaceCameraPos,
                    mul(unity_ObjectToWorld, fixed4(0,0,0,1)).xyz) > _Dst) ? -1 : 1;
                return o;
            }
            
            /*
                This layer calculates the gradients based on the B/W conversion 
                stored in the red channel. Then it uses the gradients to calc 
                and store the magnitude and direction (0 to 180 degrees) 
                inside the green and blue channels.

                In:
                    px - center sample pixel
                    xrange - clamp x between [xrange.x, xrange.y]
                    yrange - clamp y between [yrange.x, yrange.y]
                Out:
                    (magnitude, direction between 0 and 180 degrees)
            */
            float2 cartToPolar(int2 px, int2 xrange, int2 yrange) {

                // Calculating the gradient
                // Using ints instead of uints now so it doesn't overflow
                // during < 0
                int4 off = int4(clamp(px.x - 1, xrange.x, xrange.y),  //xL
                                clamp(px.x + 1, xrange.x, xrange.y),  //xH
                                clamp(px.y - 1, yrange.x, yrange.y),  //yL
                                clamp(px.y + 1, yrange.x, yrange.y)); //yH

                float3 _0 = float3(_TexBuff.Load(int3(off.x, off.z, 0.)).r,
                                   _TexBuff.Load(int3(off.x, px.y, 0.)).r,
                                   _TexBuff.Load(int3(off.x, off.w, 0.)).r);

                float3 _1 = float3(_TexBuff.Load(int3(px.x, off.z, 0.)).r,
                                   0.,
                                   _TexBuff.Load(int3(px.x, off.w, 0.)).r);

                float3 _2 = float3(_TexBuff.Load(int3(off.y, off.z, 0.)).r,
                                   _TexBuff.Load(int3(off.y, px.y, 0.)).r,
                                   _TexBuff.Load(int3(off.y, off.w, 0.)).r);

                double4 g;
                g.x = _0.x * fX[0][0] + _0.z * fX[0][2] +
                _1.x * fX[1][0] + _1.z * fX[1][2] +
                _2.x * fX[2][0] + _2.z * fX[2][2];

                g.y = _0.x * fY[0][0] + _0.y * fY[0][1] + _0.z * fY[0][2] +
                _2.x * fY[2][0] + _2.y * fY[2][1] + _2.z * fY[2][2];

                // Magnitude
                g.z = sqrt(g.y*g.y+g.x*g.x);
                // Direction (0 to 180 degrees)
                g.w = atan2(g.y, g.x) * 180.0 / UNITY_PI;
                g.w = g.w < 0.0 ? g.w + 360.0 : g.w;
                g.w = g.w > 180.0 ? g.w - 180.0 : g.w;

                // if (px.x == 0)
                //     if (px.y == 0)
                //         buffer[0] = float4(_2, 0);

                return g.zw;
            }

            float4 frag (v2f ps) : SV_Target
            {
                clip(ps.uv.z);
                int2 px = round(ps.uv.xy * outRes);
                
                float3 col = float3(0.,0.,0.);
                // I don't know what to do anymore. I think this fixes the 
                // stupid problem that OpenCV start 0,0 at the top left by 
                // flipping the camera input upside down.
                float3 camTex = _TexCam.Load(int3(px.x, outRes.y - px.y, 0));
                // Color correction
                camTex = pow(camTex, 0.45);
                //col.r = 0.3333*camTex.r + 0.3334*camTex.g + 0.3333*camTex.b;
                col.r = 0.2126*camTex.r + 0.7152*camTex.g + 0.0722*camTex.b;
                col.gb = cartToPolar(px, int2(0, outRes.x), int2(0, outRes.y));

                return float4(col, 1.0);
            }

            ENDCG
        }
    }
    FallBack "Diffuse"
}
