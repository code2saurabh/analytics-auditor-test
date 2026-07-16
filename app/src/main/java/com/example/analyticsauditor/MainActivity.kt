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

    // Two controls we already know get captured, then the analytics endpoints.
    // If the controls appear in the HAR and the analytics ones do not, BrowserStack
    // is excluding analytics domains from its proxy — which would end the
    // BrowserStack route for this project.
    private fun targets() = listOf(
        "CONTROL  gstatic"          to "https://www.gstatic.com/generate_204?auditor=$runId",
        "CONTROL  example.com"      to "https://example.com/?auditor=$runId",
        "TARGET   app-measurement"  to "https://app-measurement.com/?auditor=$runId",
        "TARGET   google-analytics" to "https://www.google-analytics.com/g/collect?v=2&tid=G-AUDITOR&cid=$runId&en=canary_event",
        "TARGET   firebase-install" to "https://firebaseinstallations.googleapis.com/?auditor=$runId"
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val root = LinearLayout(this)
        root.orientation = LinearLayout.VERTICAL
        root.setPadding(40, 80, 40, 40)

        val title = TextView(this)
        title.text = "Analytics Auditor Test\nRUN ID: $runId"
        title.textSize = 18f
        root.addView(title)

        root.addView(button("1. TEST ALL 5 ENDPOINTS") { sendAll() })
        root.addView(button("2. FIRE 25 FIREBASE EVENTS") { repeat(25) { sendFirebaseEvent() } })

        status = TextView(this)
        status.textSize = 12f
        val scroll = ScrollView(this)
        scroll.addView(status)
        root.addView(scroll)

        setContentView(root)

        log("app started, run id $runId")
        initFirebase()

        // Fire automatically, so the answer is on screen without any tapping.
        ui.postDelayed({ sendAll() }, 1500)
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
        val instance = fa ?: run { log("no FirebaseAnalytics instance"); return }
        counter++
        val params = Bundle()
        params.putString("source", "auditor_test")
        params.putString("run_id", runId)
        params.putLong("n", counter.toLong())
        instance.logEvent("test_event", params)
        if (counter % 25 == 0 || counter == 1) log("logEvent test_event #$counter (handed to SDK)")
    }

    private fun sendAll() {
        for ((label, url) in targets()) hit(label, url)
    }

    private fun hit(label: String, urlString: String) {
        Thread {
            try {
                val conn = URL(urlString).openConnection() as HttpURLConnection
                conn.connectTimeout = 10000
                conn.readTimeout = 10000
                conn.requestMethod = "GET"
                val code = conn.responseCode
                conn.disconnect()
                ui.post { log("$label -> HTTP $code") }
            } catch (t: Throwable) {
                ui.post { log("$label FAILED -> ${t.javaClass.simpleName}") }
            }
        }.start()
    }

    private fun log(msg: String) {
        Log.i(TAG, msg)
        status.text = "${status.text}\n$msg"
    }
}
