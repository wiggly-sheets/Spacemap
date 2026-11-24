import Cocoa

extension WindowDragHandler {
    func enqueueDelivery(_ delivery: DragDelivery) {
        if case .hover = delivery, case .drop = pendingDelivery { return }
        pendingDelivery = delivery
        schedulePendingDelivery()
    }

    func schedulePendingDelivery() {
        guard !isDeliveryScheduled, pendingDelivery != nil else { return }
        isDeliveryScheduled = true
        let generation = deliveryGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isDeliveryScheduled = false
            // Check generation before touching the queue: a newer delivery may
            // belong to the current generation while this block is stale.
            guard generation == self.deliveryGeneration else {
                self.schedulePendingDelivery()
                return
            }
            guard let delivery = self.pendingDelivery else { return }
            self.pendingDelivery = nil
            switch delivery {
            case .hover(let cell):
                self.onHoverCell?(cell)
            case .drop(let windowID, let cell, let modifiers):
                self.onHoverCell?(nil)
                self.onDropInCell?(windowID, cell, modifiers)
            }
        }
    }

    func cancelHoverForTeardown() {
        guard lastHoveredCell != nil || isDragging else { return }
        lastHoveredCell = nil
        onHoverCell?(nil)
    }

    func invalidateQueuedDelivery() {
        deliveryGeneration += 1
        pendingDelivery = nil
        isDeliveryScheduled = false
    }
}
