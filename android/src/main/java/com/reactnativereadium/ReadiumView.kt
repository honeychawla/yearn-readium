package com.reactnativereadium

import android.graphics.Color
import android.util.Log
import android.view.Choreographer
import android.widget.FrameLayout
import androidx.fragment.app.FragmentActivity
import com.facebook.react.bridge.Arguments
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.events.RCTEventEmitter
import com.reactnativereadium.reader.BaseReaderFragment
import com.reactnativereadium.reader.EpubReaderFragment
import com.reactnativereadium.reader.ReaderViewModel
import com.reactnativereadium.reader.VisualReaderFragment
import com.reactnativereadium.utils.Dimensions
import com.reactnativereadium.utils.File
import com.reactnativereadium.utils.LinkOrLocator
import org.json.JSONArray
import org.json.JSONObject
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.ExperimentalDecorator
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.extensions.toMap
import org.readium.r2.shared.publication.Locator

@OptIn(ExperimentalDecorator::class)
class ReadiumView(
  val reactContext: ThemedReactContext
) : FrameLayout(reactContext) {
  var dimensions: Dimensions = Dimensions(0,0)
  var file: File? = null
  var fragment: BaseReaderFragment? = null
  var isViewInitialized: Boolean = false
  var lateInitSerializedUserPreferences: String? = null

  fun updateLocation(location: LinkOrLocator) : Boolean {
    if (fragment == null) {
      return false
    } else {
      return this.fragment!!.go(location, true)
    }
  }

  fun updatePreferencesFromJsonString(preferences: String?) {
    lateInitSerializedUserPreferences = preferences
    if (preferences == null || fragment == null) {
      return
    }

    if (fragment is EpubReaderFragment) {
      (fragment as EpubReaderFragment).updatePreferencesFromJsonString(preferences)
    }
  }

  /**
   * Apply decorations from JavaScript
   */
  fun applyDecorations(decorationsJson: String?) {
    if (decorationsJson == null || fragment == null) {
      return
    }

    val decorations = parseDecorationsFromJson(decorationsJson)
    if (fragment is EpubReaderFragment) {
      (fragment as EpubReaderFragment).model.applyDecorations(decorations)
    }
  }

  /**
   * Parse JSON array of decorations into Decoration objects
   */
  private fun parseDecorationsFromJson(json: String): List<Decoration> {
    try {
      val jsonArray = JSONArray(json)
      return (0 until jsonArray.length()).mapNotNull { i ->
        try {
          val obj = jsonArray.getJSONObject(i)
          val id = obj.getString("id")
          val locatorJson = obj.getJSONObject("locator")
          val locator = Locator.fromJSON(JSONObject(locatorJson.toString()))
            ?: return@mapNotNull null

          val styleObj = obj.getJSONObject("style")
          val styleType = styleObj.getString("type")
          val colorHex = styleObj.optString("color", "#FFFF00")
          val color = parseColor(colorHex)

          val style = when (styleType) {
            "underline" -> Decoration.Style.Underline(tint = color)
            else -> Decoration.Style.Highlight(tint = color)
          }

          Decoration(id = id, locator = locator, style = style)
        } catch (e: Exception) {
          Log.e("ReadiumView", "Error parsing decoration", e)
          null
        }
      }
    } catch (e: Exception) {
      Log.e("ReadiumView", "Error parsing decorations JSON", e)
      return emptyList()
    }
  }

  /**
   * Parse hex color string to Android color int
   */
  private fun parseColor(hex: String): Int {
    return try {
      Color.parseColor(hex)
    } catch (e: Exception) {
      Color.YELLOW // Default fallback
    }
  }

  fun addFragment(frag: BaseReaderFragment) {
    fragment = frag
    setupLayout()
    lateInitSerializedUserPreferences?.let { updatePreferencesFromJsonString(it)}
    val activity: FragmentActivity? = reactContext.currentActivity as FragmentActivity?
    activity!!.supportFragmentManager
      .beginTransaction()
      .replace(this.id, frag, this.id.toString())
      .commit()

    val module = reactContext.getJSModule(RCTEventEmitter::class.java)
    // subscribe to reader events
    frag.channel.receive(frag) { event ->
      when (event) {
        is ReaderViewModel.Event.LocatorUpdate -> {
          val json = event.locator.toJSON()
          val payload = Arguments.makeNativeMap(json.toMap())
          module.receiveEvent(
            this.id.toInt(),
            ReadiumViewManager.ON_LOCATION_CHANGE,
            payload
          )
        }
        is ReaderViewModel.Event.TableOfContentsLoaded -> {
          val map = event.toc.map { it.toJSON().toMap() }
          val payload = Arguments.makeNativeMap(mapOf("toc" to map))
          module.receiveEvent(
            this.id.toInt(),
            ReadiumViewManager.ON_TABLE_OF_CONTENTS,
            payload
          )
        }
        is ReaderViewModel.Event.DecorationTapped -> {
          val payload = Arguments.createMap().apply {
            putString("decorationId", event.decorationId)
            putMap("locator", Arguments.makeNativeMap(event.locator.toJSON().toMap()))
            putString("style", event.style)
          }
          module.receiveEvent(
            this.id.toInt(),
            ReadiumViewManager.ON_DECORATION_TAPPED,
            payload
          )
        }
        is ReaderViewModel.Event.TextSelected -> {
          val payload = Arguments.createMap().apply {
            putString("selectedText", event.selectedText)
            putMap("locator", Arguments.makeNativeMap(event.locator.toJSON().toMap()))
          }
          module.receiveEvent(
            this.id.toInt(),
            ReadiumViewManager.ON_TEXT_SELECTED,
            payload
          )
        }
        else -> {
          // do nothing
        }
      }
    }
  }

  private fun setupLayout() {
    Choreographer.getInstance().postFrameCallback(object : Choreographer.FrameCallback {
      override fun doFrame(frameTimeNanos: Long) {
        manuallyLayoutChildren()
        this@ReadiumView.viewTreeObserver.dispatchOnGlobalLayout()
        Choreographer.getInstance().postFrameCallback(this)
      }
    })
  }

  /**
   * Layout all children properly
   */
  private fun manuallyLayoutChildren() {
    // propWidth and propHeight coming from react-native props
    val width = dimensions.width
    val height = dimensions.height
    this.measure(
      MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY),
      MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY))
    this.layout(0, 0, width, height)
  }
}
