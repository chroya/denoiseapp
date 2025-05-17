package com.fryant.denoise;

import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.WindowManager;
import androidx.appcompat.app.AppCompatActivity;

public class Splash extends AppCompatActivity {

    private static final long SPLASH_DELAY = 4000; // 4秒

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN); // 隐藏状态栏
        if (getSupportActionBar() != null) {
            getSupportActionBar().hide(); // 隐藏标题栏
        }
        setContentView(R.layout.activity_splash);
        getWindow().setBackgroundDrawableResource(R.drawable.splashgo);
        
        // 使用 Handler 替代 Thread，这是更好的实践
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            Intent intent = new Intent(this, MainActivity.class);
            startActivity(intent);
            finish();
        }, SPLASH_DELAY);
    }
}