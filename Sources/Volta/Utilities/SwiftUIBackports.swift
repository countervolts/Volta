import SwiftUI
import UIKit

extension View {
    @ViewBuilder
    func containerRelativeFrameCompat(count: Int, span: Int, spacing: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            self.containerRelativeFrame(.horizontal, count: count, span: span, spacing: spacing)
        } else {
            self.frame(width: Self.compatRelativeWidth(count: count, span: span, spacing: spacing))
        }
    }

    @ViewBuilder
    func scrollTargetLayoutCompat() -> some View {
        if #available(iOS 17.0, *) {
            self.scrollTargetLayout()
        } else {
            self
        }
    }

    @ViewBuilder
    func scrollTargetBehaviorCompat() -> some View {
        if #available(iOS 17.0, *) {
            self.scrollTargetBehavior(.viewAligned)
        } else {
            self
        }
    }

    @ViewBuilder
    func navigationDestinationItemCompat<Item: Identifiable & Hashable, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        modifier(NavigationDestinationItemCompatModifier(item: item, destination: destination))
    }

    @ViewBuilder
    func popoverPresentationCompactAdaptationCompat() -> some View {
        if #available(iOS 16.4, *) {
            self.presentationCompactAdaptation(.popover)
        } else {
            self
        }
    }

    @ViewBuilder
    func symbolBounceCompat<Value: Equatable>(value: Value) -> some View {
        if #available(iOS 17.0, *) {
            self.symbolEffect(.bounce, value: value)
        } else {
            self
        }
    }

    @ViewBuilder
    func symbolPulseRepeatingCompat() -> some View {
        if #available(iOS 17.0, *) {
            self.symbolEffect(.pulse, options: .repeating)
        } else {
            self
        }
    }

    @ViewBuilder
    func symbolVariableColorCompat(isActive: Bool) -> some View {
        if #available(iOS 17.0, *) {
            self.symbolEffect(.variableColor.iterative.reversing, isActive: isActive)
        } else {
            self
        }
    }

    @ViewBuilder
    func symbolVariableColorRepeatingCompat() -> some View {
        if #available(iOS 17.0, *) {
            self.symbolEffect(.variableColor.iterative, options: .repeating)
        } else {
            self
        }
    }

    func onChangeCompat<Value: Equatable>(of value: Value, _ action: @escaping () -> Void) -> some View {
        modifier(OnChangeCompatModifier(value: value) { _, _ in
            action()
        })
    }

    func onChangeCompat<Value: Equatable>(of value: Value, _ action: @escaping (Value) -> Void) -> some View {
        modifier(OnChangeCompatModifier(value: value) { _, newValue in
            action(newValue)
        })
    }

    func onChangeCompat<Value: Equatable>(
        of value: Value,
        _ action: @escaping (Value, Value) -> Void
    ) -> some View {
        modifier(OnChangeCompatModifier(value: value, action: action))
    }

    private static func compatRelativeWidth(count: Int, span: Int, spacing: CGFloat) -> CGFloat {
        let contentWidth = max(1, UIScreen.main.bounds.width - (Theme.Layout.screenPadding * 2))
        let slots = max(1, count)
        let usedSpacing = CGFloat(max(0, slots - 1)) * spacing
        let unit = max(1, contentWidth - usedSpacing) / CGFloat(slots)
        return (unit * CGFloat(max(1, span))) + (CGFloat(max(0, span - 1)) * spacing)
    }
}

private struct NavigationDestinationItemCompatModifier<Item: Identifiable & Hashable, Destination: View>: ViewModifier {
    @Binding var item: Item?
    let destination: (Item) -> Destination

    @State private var presentedItem: Item?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.navigationDestination(item: $item, destination: destination)
        } else {
            content
                .onAppear {
                    if presentedItem == nil, let item {
                        presentedItem = item
                    }
                }
                .onChangeCompat(of: item) { _, newValue in
                    presentedItem = newValue
                }
                .navigationDestination(isPresented: isPresented) {
                    if let presentedItem {
                        destination(presentedItem)
                    }
                }
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { presentedItem != nil },
            set: { isActive in
                if !isActive {
                    presentedItem = nil
                    item = nil
                }
            }
        )
    }
}

private struct OnChangeCompatModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let action: (Value, Value) -> Void

    @State private var previousValue: Value?

    func body(content: Content) -> some View {
        content
            .onAppear {
                if previousValue == nil {
                    previousValue = value
                }
            }
            .onChange(of: value) { newValue in
                let oldValue = previousValue ?? newValue
                previousValue = newValue
                action(oldValue, newValue)
            }
    }
}
