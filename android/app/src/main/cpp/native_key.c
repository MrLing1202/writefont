#include <jni.h>
#include <string.h>
#include <stdint.h>
#include <openssl/evp.h>

// AES-256-GCM encrypted API key data
// Format: [12-byte IV][ciphertext][16-byte GCM tag]
// Encrypted with PBKDF2-derived key (password + salt, 10000 iterations)
// No plaintext API key exists in this file
static const unsigned char encrypted_key_data[] = {
    0xf5, 0x5f, 0x00, 0xca, 0x9d, 0x38, 0x9f, 0x11, 0xe4, 0x2f, 0xe5, 0x4b,
    0xbf, 0x9c, 0x91, 0xae, 0x43, 0xb6, 0xcb, 0x24, 0xca, 0x70, 0x3e, 0x98,
    0x03, 0x16, 0x57, 0x78, 0x1d, 0xb8, 0x32, 0x41, 0x28, 0xdf, 0x91, 0xfb,
    0x5b, 0x67, 0xb2, 0x1b, 0xfa, 0x23, 0xf8, 0x0a, 0x9b, 0x3f, 0x7f, 0x6e,
    0xfd, 0xba, 0x27, 0xc3, 0x5e, 0xdc, 0x12, 0xd2, 0x50, 0xf4, 0xd7, 0xe0,
    0x9f, 0x8e, 0xa6, 0xc0, 0xfa, 0x7e, 0x80, 0xde, 0x73, 0x33, 0x09, 0x37,
    0x68, 0x43, 0xae, 0x34, 0x2f, 0xf0, 0x34
};
static const int encrypted_key_len = 79;

// PBKDF2 parameters (must match the values used for encryption)
static const char *pbkdf2_password = "writefont-aes256-gcm-2024";
static const char *pbkdf2_salt = "wf-native-key-salt";
static const int pbkdf2_iterations = 10000;

// JNI 解密函数 — AES-256-GCM 解密
JNIEXPORT jstring JNICALL
Java_com_writefont_app_NativeKeyProvider_getKey(JNIEnv *env, jobject thiz) {
    // PBKDF2 派生 256-bit 密钥
    unsigned char derived_key[32];
    if (PKCS5_PBKDF2_HMAC(
            pbkdf2_password, (int)strlen(pbkdf2_password),
            (const unsigned char *)pbkdf2_salt, (int)strlen(pbkdf2_salt),
            pbkdf2_iterations,
            EVP_sha256(),
            32, derived_key) != 1) {
        return (*env)->NewStringUTF(env, "");
    }

    // 提取 IV (前 12 字节) 和密文+Tag (剩余字节)
    const unsigned char *iv = encrypted_key_data;
    const unsigned char *ciphertext = encrypted_key_data + 12;
    int ciphertext_len = encrypted_key_len - 12; // 包含 16 字节 GCM tag

    // AES-256-GCM 解密
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) {
        return (*env)->NewStringUTF(env, "");
    }

    unsigned char plaintext[64];
    int out_len = 0;
    int total_len = 0;
    jstring result = NULL;

    do {
        if (EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL) != 1) break;
        if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, NULL) != 1) break;
        if (EVP_DecryptInit_ex(ctx, NULL, NULL, derived_key, iv) != 1) break;
        if (EVP_DecryptUpdate(ctx, plaintext, &out_len, ciphertext, ciphertext_len - 16) != 1) break;
        total_len = out_len;
        if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, 16,
                (void *)(ciphertext + ciphertext_len - 16)) != 1) break;
        if (EVP_DecryptFinal_ex(ctx, plaintext + total_len, &out_len) != 1) break;
        total_len += out_len;
        plaintext[total_len] = '\0';
        result = (*env)->NewStringUTF(env, (const char *)plaintext);
    } while (0);

    // 清理敏感数据
    OPENSSL_cleanse(derived_key, sizeof(derived_key));
    OPENSSL_cleanse(plaintext, sizeof(plaintext));
    EVP_CIPHER_CTX_free(ctx);

    return result ? result : (*env)->NewStringUTF(env, "");
}
