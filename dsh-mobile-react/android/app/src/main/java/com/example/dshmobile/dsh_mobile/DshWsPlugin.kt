// DshWsPlugin：原生 WebSocket 下行通道（OkHttp）。
// 背景：dsh 的 /api 信任栅栏要求浏览器请求 Origin authority == Host 且拒绝
// Sec-Fetch-Site: cross-site，WebView 页面源是 http://localhost，访问设备必然
// 跨源 → 浏览器 WebSocket 一律 403。原生请求不带这些头，与 dart:io/Node 一致。
// 纯下行：只有 connect/close，事件经 notifyListeners 推送（open/message/error/closed）。
package com.example.dshmobile.dsh_mobile

import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

@CapacitorPlugin(name = "DshWs")
class DshWsPlugin : Plugin() {
    private val client = OkHttpClient()
    private val sockets = ConcurrentHashMap<String, WebSocket>()
    private val seq = AtomicInteger(0)

    @PluginMethod
    fun connect(call: PluginCall) {
        val url = call.getString("url")
        if (url.isNullOrEmpty()) {
            call.reject("url 不能为空")
            return
        }
        val id = "ws-${seq.incrementAndGet()}"
        // 立即返回 id，连接结果走 open/error/closed 事件
        client.newWebSocket(
            Request.Builder().url(url).build(),
            object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    sockets[id] = webSocket
                    emit("open", id, null)
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    emit("message", id, text)
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    sockets.remove(id)
                    emit("error", id, t.message)
                    emit("closed", id, t.message)
                }

                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                    webSocket.close(code, reason)
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    sockets.remove(id)
                    emit("closed", id, reason.ifEmpty { null })
                }
            },
        )
        call.resolve(JSObject().put("id", id))
    }

    @PluginMethod
    fun close(call: PluginCall) {
        val id = call.getString("id")
        sockets.remove(id)?.close(1000, "client close")
        call.resolve()
    }

    override fun handleOnDestroy() {
        for (ws in sockets.values) ws.close(1001, "app destroy")
        sockets.clear()
        client.dispatcher.executorService.shutdown()
    }

    private fun emit(event: String, id: String, data: String?) {
        val payload = JSObject().put("id", id)
        if (data != null) payload.put("data", data)
        notifyListeners(event, payload)
    }
}
