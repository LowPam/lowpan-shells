pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.iris.style

SelectionGroupButton {
    id: root
    // iRiS: quiet translucent choices on black, the accent marks the selected one
    // (the same pairing as the edit toolbar's committing action).
    implicitHeight: 32

    // Override the inherited family-aware bindings only while iRiS owns this
    // control. Restore them verbatim when the panel family changes at runtime.
    Binding { target: root; property: "colBackground"; value: ColorUtils.applyAlpha(IrisStyle.text, 0.08) }
    Binding { target: root; property: "colBackgroundHover"; value: ColorUtils.applyAlpha(IrisStyle.text, 0.14) }
    Binding { target: root; property: "colBackgroundActive"; value: ColorUtils.applyAlpha(IrisStyle.text, 0.2) }
    Binding { target: root; property: "colBackgroundToggled"; value: IrisStyle.accent }
    Binding { target: root; property: "colBackgroundToggledHover"; value: Qt.lighter(IrisStyle.accent, 1.08) }
    StyledToolTip { text: root.buttonText }
}
