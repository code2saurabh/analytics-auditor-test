package com.example.analyticsauditor

import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.google.firebase.analytics.FirebaseAnalytics
import java.net.HttpURLConnection
import java.net.URL

class MainActivity : Activity() {

    private val TAG = "AUDITOR"
    private val runId = (100000..999999).random().toString()

    private lateinit var status: TextView
    private val ui = Handler(Looper.getMainLooper())
    private var fa: FirebaseAnalytics? = null
    private var counter = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val root = LinearLayout(this)
        root.orientation = LinearLayout.VERTICAL
        root.setPadding(40, 80, 40, 40)

        val title = TextView(this)
        title.text = "Analytics Auditor Test\nRUN ID: $runId"
        title.textSize = 18f
        root.addView(title)

        root.addView(button("1. Canary HTTPS request") { sendCanary() })
        root.addView(button("2. Firebase test_event") { sendFirebaseEvent() })
        root.addView(button("3. Fire 25 Firebase events") { repeat(25) { sendFirebaseEvent() } })

        status = TextView(this)
        status.textSize = 12f
        val scroll = ScrollView(this)
        scroll.addView(status)
        root.addView(scroll)

        setContentView(root)

        log("app started, run id $runId")
        initFirebase()

        // Fire automatically as well, in case tapping is fiddly on a remote device.
        ui.postDelayed({ sendCanary() }, 1500)
        ui.postDelayed({ sendFirebaseEvent() }, 3000)
    }

    private fun button(label: String, action: () -> Unit): Button {
        val b = Button(this)
        b.text = label
        b.setOnClickListener { action() }
        return b
    }

    private fun initFirebase() {
        try {
            val instance = FirebaseAnalytics.getInstance(this)
            instance.setAnalyticsCollectionEnabled(true)
            instance.setUserProperty("auditor_run", runId)
            fa = instance
            log("Firebase Analytics initialised OK")
        } catch (t: Throwable) {
            log("FIREBASE INIT FAILED -> $t")
        }
    }

    private fun sendFirebaseEvent() {
        val instance = fa
        if (instance == null) {
            log("no FirebaseAnalytics instance - event NOT sent")
            return
        }
        counter++
        val params = Bundle()
        params.putString("source", "auditor_test")
        params.putString("run_id", runId)
        params.putLong("n", counter.toLong())
        instance.logEvent("test_event", params)
        log("logEvent test_event #$counter (handed to SDK)")
    }

    private fun sendCanary() {
        canary("https://www.gstatic.com/generate_204?auditor=$runId")
        canary("https://app-measurement.com/?auditor=$runId")
    }

    private fun canary(urlString: String) {
        Thread {
            val host = try {
                URL(urlString).host
            } catch (t: Throwable) {
                urlString
            }
            try {
                val conn = URL(urlString).openConnection() as HttpURLConnection
                conn.connectTimeout = 10000
                conn.readTimeout = 10000
                conn.requestMethod = "GET"
                val code = conn.responseCode
                conn.disconnect()
                ui.post { log("canary $host -> HTTP $code") }
            } catch (t: Throwable) {
                ui.post { log("canary $host FAILED -> ${t.javaClass.simpleName}: ${t.message}") }
            }
        }.start()
    }

    private fun log(msg: String) {
        Log.i(TAG, msg)
        status.text = "${status.text}\n$msg"
    }
}
