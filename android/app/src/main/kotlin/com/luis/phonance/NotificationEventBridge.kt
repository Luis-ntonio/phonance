package com.luis.phonance

import io.flutter.plugin.common.EventChannel
import java.util.concurrent.atomic.AtomicReference

object NotificationEventBridge : EventChannel.StreamHandler {

    private val sinkRef = AtomicReference<EventChannel.EventSink?>(null)

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sinkRef.set(events)
    }

    override fun onCancel(arguments: Any?) {
        sinkRef.set(null)
    }

    fun emit(map: Map<String, Any?>) {
        sinkRef.get()?.success(map)
    }
}
