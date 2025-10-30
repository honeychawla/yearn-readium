/*
 * Copyright 2021 Readium Foundation. All rights reserved.
 * Use of this source code is governed by the BSD-style license
 * available in the top-level LICENSE file of the project.
 */

package com.reactnativereadium.reader

import android.graphics.Color
import android.graphics.PointF
import android.os.Bundle
import android.view.*
import android.view.accessibility.AccessibilityManager
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.SearchView
import androidx.fragment.app.commitNow
import androidx.lifecycle.ViewModelProvider
import com.reactnativereadium.R
import com.reactnativereadium.utils.toggleSystemUi
import java.net.URL
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import androidx.lifecycle.lifecycleScope
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.ExperimentalDecorator
import org.readium.r2.navigator.Navigator
import org.readium.r2.navigator.DecorableNavigator
import org.readium.r2.navigator.SelectableNavigator
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.epub.EpubPreferencesSerializer
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.ReadiumCSSName

@OptIn(ExperimentalDecorator::class)
class EpubReaderFragment : VisualReaderFragment(), EpubNavigatorFragment.Listener {

    public override lateinit var model: ReaderViewModel
    override lateinit var navigator: Navigator
    private lateinit var publication: Publication
    lateinit var navigatorFragment: EpubNavigatorFragment
    private lateinit var factory: ReaderViewModel.Factory
    private var initialPreferencesJsonString: String? = null

    private lateinit var menuScreenReader: MenuItem
    private lateinit var menuSearch: MenuItem
    lateinit var menuSearchView: SearchView

    private lateinit var userPreferences: EpubPreferences
    private var isScreenReaderVisible = false
    private var isSearchViewIconified = true

    // Accessibility
    private var isExploreByTouchEnabled = false

    fun initFactory(
      publication: Publication,
      initialLocation: Locator?
    ) {
      factory = ReaderViewModel.Factory(
        publication,
        initialLocation
      )
    }

    fun updatePreferencesFromJsonString(serialisedPreferences: String) {
      if (this::userPreferences.isInitialized) {
        val serializer = EpubPreferencesSerializer()
        this.userPreferences = serializer.deserialize(serialisedPreferences)
        if (navigator is EpubNavigatorFragment) {
          (navigator as EpubNavigatorFragment).submitPreferences(this.userPreferences)
        }
        initialPreferencesJsonString = null
      } else {
        initialPreferencesJsonString = serialisedPreferences
      }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // FIXME: this should be checked
        // check(R2App.isServerStarted)

        if (savedInstanceState != null) {
            isScreenReaderVisible = savedInstanceState.getBoolean(IS_SCREEN_READER_VISIBLE_KEY)
            isSearchViewIconified = savedInstanceState.getBoolean(IS_SEARCH_VIEW_ICONIFIED)
        }

        ViewModelProvider(this, factory)
          .get(ReaderViewModel::class.java)
          .let {
            model = it
            publication = it.publication
          }


        childFragmentManager.fragmentFactory =
            EpubNavigatorFragment.createFactory(
                publication = publication,
                initialLocator = model.initialLocation,
                listener = this,
                config = EpubNavigatorFragment.Configuration().apply {
                    // Custom text selection callback to add "Highlight" action
                    selectionActionModeCallback = createSelectionActionCallback()
                }
            )

        setHasOptionsMenu(true)

        super.onCreate(savedInstanceState)
    }

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View? {
        val view = super.onCreateView(inflater, container, savedInstanceState)
        val navigatorFragmentTag = getString(R.string.epub_navigator_tag)

        if (savedInstanceState == null) {
            childFragmentManager.commitNow {
                add(R.id.fragment_reader_container, EpubNavigatorFragment::class.java, Bundle(), navigatorFragmentTag)
            }
        }
        navigator = childFragmentManager.findFragmentByTag(navigatorFragmentTag) as Navigator
        navigatorFragment = navigator as EpubNavigatorFragment

        return view
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        // Observe and apply user decorations
        viewLifecycleOwner.lifecycleScope.launch {
            model.userDecorations.collect { decorations ->
                (navigator as? DecorableNavigator)?.applyDecorations(
                    decorations = decorations,
                    group = "user-highlights"
                )
            }
        }

        // TODO: Add decoration tap observer once we find the correct Readium 2.4.1 API
        // For now, decorations will render but won't be interactive
    }

    private fun createSelectionActionCallback(): ActionMode.Callback {
        return object : ActionMode.Callback {
            override fun onCreateActionMode(mode: ActionMode?, menu: Menu?): Boolean {
                // Add "Highlight" action to selection menu
                menu?.add(0, MENU_ITEM_HIGHLIGHT, 0, "Highlight")
                return true
            }

            override fun onPrepareActionMode(mode: ActionMode?, menu: Menu?): Boolean {
                return false
            }

            override fun onActionItemClicked(mode: ActionMode?, item: MenuItem?): Boolean {
                return when (item?.itemId) {
                    MENU_ITEM_HIGHLIGHT -> {
                        handleTextSelection()
                        mode?.finish()
                        true
                    }
                    else -> false
                }
            }

            override fun onDestroyActionMode(mode: ActionMode?) {
                // Selection dismissed
            }
        }
    }

    private fun handleTextSelection() {
        android.util.Log.d("EpubReader", "handleTextSelection called")
        viewLifecycleOwner.lifecycleScope.launch {
            val selectableNavigator = navigatorFragment as? SelectableNavigator
            if (selectableNavigator == null) {
                android.util.Log.e("EpubReader", "Navigator is not SelectableNavigator")
                return@launch
            }

            val selection = selectableNavigator.currentSelection()
            if (selection == null) {
                android.util.Log.e("EpubReader", "No selection available")
                return@launch
            }

            // Extract selected text and locator
            val selectedText = selection.locator.text?.highlight ?: ""
            android.util.Log.d("EpubReader", "Selected text: $selectedText")

            // Send to the fragment's channel
            channel.send(
                ReaderViewModel.Event.TextSelected(
                    selectedText = selectedText,
                    locator = selection.locator
                )
            )
            android.util.Log.d("EpubReader", "TextSelected event sent")
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putBoolean(IS_SCREEN_READER_VISIBLE_KEY, isScreenReaderVisible)
        outState.putBoolean(IS_SEARCH_VIEW_ICONIFIED, isSearchViewIconified)
    }

    override fun onTap(point: PointF): Boolean {
        return true
    }

    companion object {

        private const val SEARCH_FRAGMENT_TAG = "search"

        private const val IS_SCREEN_READER_VISIBLE_KEY = "isScreenReaderVisible"

        private const val IS_SEARCH_VIEW_ICONIFIED = "isSearchViewIconified"

        private const val MENU_ITEM_HIGHLIGHT = 1

        fun newInstance(): EpubReaderFragment {
            return EpubReaderFragment()
        }
    }
}
