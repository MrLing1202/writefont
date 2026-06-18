package com.writefont.app;

public class NativeKeyProvider {
    static {
        System.loadLibrary("native_key");
    }

    public native String getKey();
}
