#include <jni.h>
#include <string.h>
#include <stdint.h>
#include <stdio.h>

// Key 分段加密数据（从 api_key.dart 迁移过来）
// 这些字节是 XOR 加密后的，运行时解密
static const unsigned char s0[] = {57, 161, 202, 181, 103, 243, 96, 97, 147, 141, 141, 251};
static const unsigned char s1[] = {111, 49, 117, 186, 3, 0, 194, 157, 138, 63, 20, 101};
static const unsigned char s2[] = {209, 120, 73, 18, 132, 147, 167, 200, 135, 127, 189, 136};
static const unsigned char s3[] = {144, 146, 62, 30, 93, 213, 6, 172, 9, 156, 135, 77, 167, 12, 16};

// SHA-256 常量
static const uint32_t K[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

#define ROTR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))
#define CH(x, y, z)  (((x) & (y)) ^ (~(x) & (z)))
#define MAJ(x, y, z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define EP0(x) (ROTR(x, 2) ^ ROTR(x, 13) ^ ROTR(x, 22))
#define EP1(x) (ROTR(x, 6) ^ ROTR(x, 11) ^ ROTR(x, 25))
#define SIG0(x) (ROTR(x, 7) ^ ROTR(x, 18) ^ ((x) >> 3))
#define SIG1(x) (ROTR(x, 17) ^ ROTR(x, 19) ^ ((x) >> 10))

// 完整的 SHA-256 实现
static void sha256(const unsigned char *data, size_t len, unsigned char *hash) {
    uint32_t h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
    uint32_t h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;

    // 计算填充后的长度
    size_t bit_len = len * 8;
    size_t pad_len = len + 1;
    while (pad_len % 64 != 56) pad_len++;
    size_t total_len = pad_len + 8;

    // 按块处理
    unsigned char block[64];
    for (size_t offset = 0; offset < total_len; offset += 64) {
        memset(block, 0, 64);

        // 填充数据
        for (int i = 0; i < 64; i++) {
            size_t pos = offset + i;
            if (pos < len) {
                block[i] = data[pos];
            } else if (pos == len) {
                block[i] = 0x80;
            } else if (pos >= pad_len) {
                // 写入 64-bit 大端长度
                int shift = (7 - (pos - pad_len)) * 8;
                block[i] = (unsigned char)((bit_len >> shift) & 0xFF);
            }
        }

        // 准备消息调度
        uint32_t w[64];
        for (int i = 0; i < 16; i++) {
            w[i] = ((uint32_t)block[i * 4] << 24) |
                   ((uint32_t)block[i * 4 + 1] << 16) |
                   ((uint32_t)block[i * 4 + 2] << 8) |
                   ((uint32_t)block[i * 4 + 3]);
        }
        for (int i = 16; i < 64; i++) {
            w[i] = SIG1(w[i - 2]) + w[i - 7] + SIG0(w[i - 15]) + w[i - 16];
        }

        // 压缩
        uint32_t a = h0, b = h1, c = h2, d = h3;
        uint32_t e = h4, f = h5, g = h6, h = h7;

        for (int i = 0; i < 64; i++) {
            uint32_t t1 = h + EP1(e) + CH(e, f, g) + K[i] + w[i];
            uint32_t t2 = EP0(a) + MAJ(a, b, c);
            h = g; g = f; f = e; e = d + t1;
            d = c; c = b; b = a; a = t1 + t2;
        }

        h0 += a; h1 += b; h2 += c; h3 += d;
        h4 += e; h5 += f; h6 += g; h7 += h;
    }

    // 输出大端字节序
    for (int i = 0; i < 4; i++) {
        hash[i]      = (h0 >> (24 - i * 8)) & 0xFF;
        hash[i + 4]  = (h1 >> (24 - i * 8)) & 0xFF;
        hash[i + 8]  = (h2 >> (24 - i * 8)) & 0xFF;
        hash[i + 12] = (h3 >> (24 - i * 8)) & 0xFF;
        hash[i + 16] = (h4 >> (24 - i * 8)) & 0xFF;
        hash[i + 20] = (h5 >> (24 - i * 8)) & 0xFF;
        hash[i + 24] = (h6 >> (24 - i * 8)) & 0xFF;
        hash[i + 28] = (h7 >> (24 - i * 8)) & 0xFF;
    }
}

// JNI 解密函数 — 与 Dart ApiKeyProvider.getKey() 逻辑完全一致
JNIEXPORT jstring JNICALL
Java_com_writefont_app_NativeKeyProvider_getKey(JNIEnv *env, jobject thiz) {
    const char *salt = "writefont2024";
    const unsigned char *segments[] = {s0, s1, s2, s3};
    const int seg_lens[] = {12, 12, 12, 15};

    unsigned char result[56] = {0};
    int pos = 0;

    for (int i = 0; i < 4; i++) {
        // 构造 hash 输入: salt + index
        char hash_input[32];
        int hash_len = sprintf(hash_input, "%s%d", salt, i);

        // SHA-256 生成 key stream
        unsigned char key_stream[32];
        sha256((const unsigned char *)hash_input, hash_len, key_stream);

        // XOR 解密
        for (int j = 0; j < seg_lens[i]; j++) {
            result[pos++] = segments[i][j] ^ key_stream[j % 32];
        }
    }

    return (*env)->NewStringUTF(env, (const char *)result);
}
