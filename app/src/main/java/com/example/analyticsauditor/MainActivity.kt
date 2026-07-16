package com.example.analyticsauditor

import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.firebase.analytics.FirebaseAnalytics

class MainActivity : AppCompatActivity() {

    private lateinit var firebaseAnalytics: FirebaseAnalytics

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        firebaseAnalytics = FirebaseAnalytics.getInstance(this)

        val statusText = findViewById<TextView>(R.id.statusText)
        val testButton = findViewById<Button>(R.id.testButton)

        testButton.setOnClickListener {
            val params = Bundle().apply {
                putString("test_source", "analytics_auditor_poc")
            }
            firebaseAnalytics.logEvent("test_event", params)
            statusText.text = "test_event sent!"
        }
    }
}
