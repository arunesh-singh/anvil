// Lives in the android.print package on purpose: PrintDocumentAdapter's
// LayoutResultCallback / WriteResultCallback constructors are package-private,
// and subclassing them from here is the established way to drive a
// PrintDocumentAdapter (WebView.createPrintDocumentAdapter) headlessly.
package android.print

import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor

/** Drives a [PrintDocumentAdapter] to write a PDF into [fd], then calls [onDone]. */
object PdfPrintBridge {
    fun writeTo(
        adapter: PrintDocumentAdapter,
        attributes: PrintAttributes,
        fd: ParcelFileDescriptor,
        onDone: (error: String?) -> Unit,
    ) {
        adapter.onLayout(
            null,
            attributes,
            CancellationSignal(),
            object : PrintDocumentAdapter.LayoutResultCallback() {
                override fun onLayoutFinished(info: PrintDocumentInfo?, changed: Boolean) {
                    adapter.onWrite(
                        arrayOf(PageRange.ALL_PAGES),
                        fd,
                        CancellationSignal(),
                        object : PrintDocumentAdapter.WriteResultCallback() {
                            override fun onWriteFinished(pages: Array<out PageRange>?) {
                                onDone(null)
                            }

                            override fun onWriteFailed(error: CharSequence?) {
                                onDone(error?.toString() ?: "Could not write the PDF.")
                            }
                        },
                    )
                }

                override fun onLayoutFailed(error: CharSequence?) {
                    onDone(error?.toString() ?: "Could not lay out the page.")
                }
            },
            Bundle(),
        )
    }
}
