package com.moonbit.openseek

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/** Custom Tabs fallback. Carries a completion signal, never account credentials. */
class SignInReturnActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startActivity(Intent(this, SignInActivity::class.java).apply {
            data = intent.data
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        })
        finish()
    }
}
