package com.example.dshmobile.dsh_mobile;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
  @Override
  public void onCreate(Bundle savedInstanceState) {
    // 原生 WebSocket 下行通道（dsh /api 信任栅栏拒绝浏览器跨源 WS）
    registerPlugin(DshWsPlugin.class);
    super.onCreate(savedInstanceState);
  }
}
