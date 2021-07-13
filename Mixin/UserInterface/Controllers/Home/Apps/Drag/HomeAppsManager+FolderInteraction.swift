import Foundation

extension HomeAppsManager {
    
    @discardableResult
    func showFolder(from cell: AppFolderCell, isNewFolder: Bool = false, startInRename: Bool = false) -> HomeAppsFolderViewController {
        openFolderInfo = HomeAppsOpenFolderInfo(cell: cell, isNewFolder: isNewFolder)
        cell.stopShaking()
        let convertedFrame = cell.convert(cell.imageContainerView.frame, to: AppDelegate.current.mainWindow)
        let folderViewController = HomeAppsFolderViewController.instance()
        folderViewController.modalPresentationStyle = .overFullScreen
        folderViewController.isEditing = isEditing
        folderViewController.folder = cell.item as? AppFolderModel
        folderViewController.currentPage = cell.currentPage
        folderViewController.sourceFrame = convertedFrame
        folderViewController.startInRename = startInRename
        folderViewController.delegate = self
        if let dragInteraction = currentDragInteraction {
            folderViewController.dragInteractionTransfer = HomeAppsDragInteractionTransfer(gestureRecognizer: longPressRecognizer, interaction: dragInteraction)
            currentDragInteraction = nil
            longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPressGesture(_:)))
            viewController.view.addGestureRecognizer(longPressRecognizer)
        }
        viewController.present(folderViewController, animated: false, completion: nil)
        return folderViewController
    }
    
    func startFolderInteraction(for itemCell: AppCell) {
        guard let dragInteraction = currentDragInteraction else { return }
        folderTimer = Timer.scheduledTimer(timeInterval: HomeAppsMode.folderInterval, target: self, selector: #selector(folderTimerHandler), userInfo: nil, repeats: false)
        dragInteraction.transitionToFolderWrapperView()
        let folderWrapperView = UIView(frame: itemCell.imageContainerView.frame)
        folderWrapperView.layer.cornerRadius = 12
        folderWrapperView.backgroundColor = R.color.background_secondary()
        itemCell.contentView.insertSubview(folderWrapperView, belowSubview: itemCell.imageContainerView)
        cancelFolderInteraction()
        if let folder = itemCell.item as? AppFolderModel, let folderCell = itemCell as? AppFolderCell {
            currentFolderInteraction = HomeAppsFolderDropInteraction(dragInteraction: dragInteraction, folder: folder, wrapperView: folderWrapperView)
            folderCell.wrapperView.isHidden = false
        } else if let app = itemCell.item as? AppModel {
            currentFolderInteraction = HomeAppsFolderCreationInteraction(dragInteraction: dragInteraction, destinationApp: app, wrapperView: folderWrapperView)
        }
        itemCell.stopShaking()
        UIView.animate(withDuration: 0.25) {
            folderWrapperView.transform = CGAffineTransform.identity.scaledBy(x: 1.2, y: 1.2)
            self.currentDragInteraction?.placeholderView.transform = .identity
            itemCell.label?.alpha = 0
        }
    }
    
    func cancelFolderInteraction() {
        guard var folderInteraction = currentFolderInteraction,
              let index = folderInteraction.dragInteraction.currentPageCell.items.firstIndex(where: { $0 === folderInteraction.item }),
              let cell = folderInteraction.dragInteraction.currentPageCell.collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? AppCell,
              !folderInteraction.isDismissing else {
            return
        }
        folderInteraction.dragInteraction.transitionFromFolderWrapperView()
        folderTimer?.invalidate()
        folderTimer = nil
        currentFolderInteraction = nil
        folderInteraction.isDismissing = true
        UIView.animate(withDuration: 0.25, animations: {
            folderInteraction.wrapperView.transform = .identity
            self.currentDragInteraction?.placeholderView.transform = CGAffineTransform.identity.scaledBy(x: 1.3, y: 1.3)
            folderInteraction.dragInteraction.currentPageCell.collectionView.visibleCells.forEach { cell in
                if let cell = cell as? AppCell {
                    cell.label?.alpha = 1
                }
            }
        }, completion: { _ in
            if let folderCell = cell as? AppFolderCell {
                folderCell.wrapperView.isHidden = false
            }
            folderInteraction.wrapperView.removeFromSuperview()
            folderInteraction.dragInteraction.currentPageCell.collectionView.visibleCells.forEach { cell in
                if let cell = cell as? AppCell {
                    cell.startShaking()
                }
            }
        })
    }
    
    func showFolderInteraction(_ interaction: HomeAppsFolderInteraction, page: Int, sourceIndex: Int, destinationIndex: Int, folderIndexPath: IndexPath, isNewFolder: Bool = false) {
        let folderIndexPath = IndexPath(item: destinationIndex, section: 0)
        interaction.dragInteraction.currentPageCell.items = items[page]
        let folderCell = interaction.dragInteraction.currentPageCell.collectionView.cellForItem(at: folderIndexPath) as! AppFolderCell
        let folderViewController = showFolder(from: folderCell, isNewFolder: isNewFolder)
        folderViewController.openAnimationDidEnd = { [weak folderViewController] in
            self.items[page].remove(at: sourceIndex)
            interaction.dragInteraction.currentPageCell.items = self.items[page]
            interaction.dragInteraction.currentPageCell.collectionView.performBatchUpdates {
                interaction.dragInteraction.currentPageCell.collectionView.deleteItems(at: [IndexPath(item: sourceIndex, section: 0)])
            } completion: { _ in
                folderCell.stopShaking()
                let convertedFrame = folderCell.convert(folderCell.imageContainerView.frame, to: AppDelegate.current.mainWindow)
                folderViewController?.sourceFrame = convertedFrame
                folderCell.wrapperView.isHidden = isNewFolder
                interaction.wrapperView.removeFromSuperview()
                interaction.dragInteraction.placeholderView.removeFromSuperview()
                self.currentFolderInteraction = nil
            }
        }
    }
    
    func updateFolderDragOutFlags() {
        guard let interaction = currentDragInteraction else { return }
        if interaction.placeholderView.center.y < candidateCollectionView.superview!.frame.minY {
            ignoreDragOutOnTop = true
        } else if interaction.placeholderView.center.y > candidateCollectionView.superview!.frame.maxY {
            ignoreDragOutOnBottom = true
        }
    }
    
    func commitFolderInteraction(didDrop: Bool = false) {
        guard let folderInteraction = currentFolderInteraction, !folderInteraction.isDismissing else {
            return
        }
        updateState(forPageCell: folderInteraction.dragInteraction.currentPageCell)
        if let creationInteraction = folderInteraction as? HomeAppsFolderCreationInteraction {
            commit(folderCreationInteraction: creationInteraction, didDrop: didDrop)
        } else if let dropInteraction = folderInteraction as? HomeAppsFolderDropInteraction {
            commit(folderDropInteraction: dropInteraction, didDrop: didDrop)
        }
    }
    
    // create new folder
    private func commit(folderCreationInteraction interaction: HomeAppsFolderCreationInteraction, didDrop: Bool) {
        guard let page = items.firstIndex(where: { $0.contains { $0 === interaction.destinationApp } }),
              let sourceIndex = items[page].firstIndex(where: { $0 === interaction.dragInteraction.item }),
              let destinationIndex = items[page].firstIndex(where: { $0 === interaction.destinationApp }),
              let sourceApp = interaction.dragInteraction.item as? AppModel else {
            return
        }
        let folderName = sourceApp.app?.category ?? R.string.localizable.app_category_other()
        let newFolder = AppFolderModel(name: folderName, pages: [[interaction.destinationApp, sourceApp]])
        newFolder.isNewFolder = true
        items[page][destinationIndex] = newFolder
        let folderIndexPath = IndexPath(item: destinationIndex, section: 0)
        interaction.dragInteraction.currentPageCell.items = items[page]
        if !didDrop {
            // still press when folder was created
            interaction.dragInteraction.currentPageCell.collectionView.reloadItems(at: [folderIndexPath])
            showFolderInteraction(interaction, page: page, sourceIndex: sourceIndex, destinationIndex: destinationIndex, folderIndexPath: folderIndexPath, isNewFolder: true)
            newFolder.isNewFolder = false
        } else {
            // end press whne folder was created
            UIView.animate(withDuration: 0.25) {
                interaction.dragInteraction.placeholderView.alpha = 1
            }
            let destinationCell = interaction.dragInteraction.currentPageCell.collectionView.cellForItem(at: IndexPath(item: destinationIndex, section: 0)) as! AppCell
            let iconSnapshot = destinationCell.imageContainerView.snapshotView(afterScreenUpdates: false)!
            iconSnapshot.frame = destinationCell.convert(destinationCell.imageContainerView.frame, to: interaction.dragInteraction.currentPageCell)
            interaction.dragInteraction.currentPageCell.contentView.addSubview(iconSnapshot)
            
            let convertedIconFrame = interaction.dragInteraction.placeholderView.convert(interaction.dragInteraction.placeholderView.iconView.frame, to: interaction.dragInteraction.placeholderView.superview!)
            interaction.dragInteraction.placeholderView.iconView.frame = convertedIconFrame
            interaction.dragInteraction.placeholderView.superview!.addSubview(interaction.dragInteraction.placeholderView.iconView)
            interaction.dragInteraction.placeholderView.removeFromSuperview()
            interaction.dragInteraction.currentPageCell.collectionView.performBatchUpdates {
                interaction.dragInteraction.currentPageCell.collectionView.reloadItems(at: [folderIndexPath])
            } completion: { _ in
                let folderCell = interaction.dragInteraction.currentPageCell.collectionView.cellForItem(at: folderIndexPath) as! AppFolderCell
                folderCell.move(view: iconSnapshot, toCellPositionAtIndex: 0)
                folderCell.move(view: interaction.dragInteraction.placeholderView.iconView, toCellPositionAtIndex: 1) {
                    iconSnapshot.removeFromSuperview()
                    interaction.dragInteraction.placeholderView.iconView.removeFromSuperview()
                    self.currentFolderInteraction = nil
                    self.currentDragInteraction = nil
                    self.showFolderInteraction(interaction, page: page, sourceIndex: sourceIndex, destinationIndex: destinationIndex, folderIndexPath: folderIndexPath, isNewFolder: true)
                    newFolder.isNewFolder = false
                }
            }
        }
    }
    
    // drop into created folder
    private func commit(folderDropInteraction interaction: HomeAppsFolderDropInteraction, didDrop: Bool) {
        guard let page = items.firstIndex(where: { $0.contains { $0 === interaction.folder } }),
              let sourceIndex = items[page].firstIndex(where: { $0 === interaction.dragInteraction.item }),
              let destinationIndex = items[page].firstIndex(where: { $0 === interaction.folder }),
              let sourceApp = interaction.dragInteraction.item as? AppModel else {
            return
        }
        let folderIndexPath = IndexPath(item: destinationIndex, section: 0)
        guard let folderCell = interaction.dragInteraction.currentPageCell.collectionView.cellForItem(at: folderIndexPath) as? AppFolderCell,
              let item = folderCell.item as? AppFolderModel else {
            return
        }
        item.pages[folderCell.currentPage].append(sourceApp)
        if !didDrop {
            showFolderInteraction(interaction, page: page, sourceIndex: sourceIndex, destinationIndex: destinationIndex, folderIndexPath: folderIndexPath)
            cancelFolderInteraction()
        } else {
            UIView.animate(withDuration: 0.25) {
                interaction.dragInteraction.placeholderView.alpha = 1
            }
            let convertedIconFrame = interaction.dragInteraction.placeholderView.convert(interaction.dragInteraction.placeholderView.iconView.frame, to: interaction.dragInteraction.placeholderView.superview!)
            interaction.dragInteraction.placeholderView.iconView.frame = convertedIconFrame
            interaction.dragInteraction.placeholderView.superview!.addSubview(interaction.dragInteraction.placeholderView.iconView)
            interaction.dragInteraction.placeholderView.removeFromSuperview()
            let folderCell = interaction.dragInteraction.currentPageCell.collectionView.cellForItem(at: folderIndexPath) as! AppFolderCell
            folderCell.move(view: interaction.dragInteraction.placeholderView.iconView, toCellPositionAtIndex: item.pages[folderCell.currentPage].count - 1) {
                var didRestoreSavedState = false
                if let savedState = interaction.dragInteraction.savedState {
                    self.items = savedState
                    interaction.dragInteraction.currentPageCell.items = self.items[page]
                    didRestoreSavedState = true
                } else if folderIndexPath.row < sourceIndex {
                    self.items[page].remove(at: sourceIndex)
                    interaction.dragInteraction.currentPageCell.items = self.items[page]
                }
                self.currentFolderInteraction = nil
                self.currentDragInteraction = nil
                interaction.dragInteraction.currentPageCell.collectionView.performBatchUpdates {
                    folderCell.item = item
                    interaction.dragInteraction.placeholderView.iconView.removeFromSuperview()
                    folderCell.moveToFirstAvailablePage()
                    if folderIndexPath.row < sourceIndex {
                        interaction.dragInteraction.currentPageCell.collectionView.deleteItems(at: [IndexPath(item: sourceIndex, section: 0)])
                        if didRestoreSavedState {
                            interaction.dragInteraction.currentPageCell.collectionView.insertItems(at: [IndexPath(item: HomeAppsMode.regular.appsPerPage - 1, section: 0)])
                        }
                    }
                } completion: { _ in
                    interaction.dragInteraction.placeholderView.iconView.removeFromSuperview()
                    if folderIndexPath.row > sourceIndex {
                        if !didRestoreSavedState {
                            self.items[page].remove(at: sourceIndex)
                        }
                        interaction.dragInteraction.currentPageCell.items = self.items[page]
                        interaction.dragInteraction.currentPageCell.collectionView.performBatchUpdates({
                            interaction.dragInteraction.currentPageCell.collectionView.deleteItems(at: [IndexPath(item: sourceIndex, section: 0)])
                            if didRestoreSavedState {
                                interaction.dragInteraction.currentPageCell.collectionView.insertItems(at: [IndexPath(item: HomeAppsMode.regular.appsPerPage - 1, section: 0)])
                            }
                        }, completion: nil)
                    }
                }
            }
            UIView.animate(withDuration: 0.35) {
                interaction.wrapperView.transform = .identity
                folderCell.label?.alpha = 1
            } completion: { _ in
                interaction.wrapperView.removeFromSuperview()
                folderCell.wrapperView.isHidden = false
                folderCell.startShaking()
            }
        }
    }
    
}

extension HomeAppsManager {
    
    @objc func folderRemoveTimerHandler() {
        guard let dragInteraction = currentDragInteraction,
              let pageCellIndexPath = candidateCollectionView.indexPath(for: dragInteraction.currentPageCell) else {
            return
        }
        updateState(forPageCell: dragInteraction.currentPageCell)
        items[pageCellIndexPath.row].remove(at: dragInteraction.currentIndexPath.row)
        dragInteraction.currentPageCell.items = items[pageCellIndexPath.row]
        dragInteraction.currentPageCell.collectionView.deleteItems(at: [dragInteraction.currentIndexPath])
        let transfer = HomeAppsDragInteractionTransfer(gestureRecognizer: longPressRecognizer, interaction: dragInteraction)
        delegate?.homeAppsManager(self, didBeginFolderDragOutWithTransfer: transfer)
    }
    
    @objc func folderTimerHandler() {
        guard let folderInteraction = currentFolderInteraction, !folderInteraction.isDismissing else {
            return
        }
        folderTimer = nil
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.autoreverses = true
        animation.repeatCount = 2
        animation.toValue = 0.5
        animation.duration = 0.15
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            self.commitFolderInteraction()
        }
        folderInteraction.wrapperView.layer.add(animation, forKey: nil)
        CATransaction.commit()
    }
    
}

extension HomeAppsManager: HomeAppsFolderViewControllerDelegate {
    
    func homeAppsFolderViewControllerOpenAnimationWillStart(_ controller: HomeAppsFolderViewController) {
        guard let info = openFolderInfo else { return }
        info.cell.imageContainerView?.isHidden = true
        info.cell.wrapperView.isHidden = true
    }
    
    func homeAppsFolderViewControllerDidEnterEditingMode(_ controller: HomeAppsFolderViewController) {
        enterEditingMode()
    }
    
    func homeAppsFolderViewController(_ controller: HomeAppsFolderViewController, didChangeName name: String) {
        guard let info = openFolderInfo else { return }
        info.cell.label?.text = name
    }
    
    func homeAppsFolderViewController(_ controller: HomeAppsFolderViewController, didSelectApp app: AppModel) {
        delegate?.homeAppsManager(self, didSelectApp: app)
    }
    
    func homeAppsFolderViewController(_ controller: HomeAppsFolderViewController, didBeginFolderDragOutWithTransfer transfer: HomeAppsDragInteractionTransfer) {
        guard let info = openFolderInfo, let folderIndex = items[currentPage].firstIndex(where: { $0 === info.folder }), let pageCell = currentPageCell else {
            return
        }
        if info.folder.pages.flatMap({ $0 }).count == 0 { // last app dragged out then remove folder
            items[currentPage].append(transfer.interaction.item)
            items[currentPage].remove(at: folderIndex)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: {
                self.perform(transfer: transfer, showPlaceholder: true)
                pageCell.draggedItem = transfer.interaction.item
                pageCell.items = self.items[self.currentPage]
                self.currentDragInteraction?.currentPageCell = pageCell
                self.currentDragInteraction?.currentIndexPath = IndexPath(item: pageCell.collectionView(pageCell.collectionView, numberOfItemsInSection: 0) - 1, section: 0)
                self.currentDragInteraction?.needsUpdate = false
                pageCell.collectionView.performBatchUpdates({
                    pageCell.collectionView.deleteItems(at: [IndexPath(item: folderIndex, section: 0)])
                    pageCell.collectionView.insertItems(at: [IndexPath(item: self.items[self.currentPage].count - 1, section: 0)])
                }, completion: { _ in
                    // force end the operation.
                    if self.longPressRecognizer.state == .possible {
                        self.endDragInteraction(self.longPressRecognizer)
                    }
                })
            })
        } else { // drag out app, folder still remain more than one apps
            perform(transfer: transfer, showPlaceholder: true)
            currentDragInteraction?.currentPageCell = pageCell
            if items[currentPage].count == HomeAppsMode.regular.appsPerPage {
                currentDragInteraction?.savedState = items
                moveLastItem(inPage: currentPage)
            }
            items[currentPage].append(transfer.interaction.item)
            pageCell.draggedItem = transfer.interaction.item
            var indexPathRow = pageCell.collectionView(pageCell.collectionView, numberOfItemsInSection: 0)
            if indexPathRow == HomeAppsMode.regular.appsPerPage {
                indexPathRow -= 1
            }
            let indexPath = IndexPath(item: indexPathRow, section: 0)
            currentDragInteraction?.currentIndexPath = indexPath
            currentDragInteraction?.needsUpdate = false
            pageCell.items = items[currentPage]
            pageCell.collectionView.performBatchUpdates({
                if self.currentDragInteraction?.savedState == nil {
                    pageCell.collectionView.insertItems(at: [indexPath])
                } else {
                    pageCell.collectionView.reloadItems(at: [indexPath])
                }
            }, completion: { _ in
                if self.longPressRecognizer.state == .possible {
                    self.endDragInteraction(self.longPressRecognizer)
                }
            })
        }
        info.shouldCancelCreation = info.isNewFolder
    }
    
    func homeAppsFolderViewController(_ controller: HomeAppsFolderViewController, dismissAnimationWillStartOnPage page: Int, updatedPages: [[AppModel]]) {
        guard let info = openFolderInfo else { return }
        UIView.animate(withDuration: 0.5) {
            info.cell.imageContainerView?.isHidden = false
            info.cell.wrapperView.isHidden = false
        }
        info.folder.pages = updatedPages.filter({ $0.count != 0 })
        info.cell.item = info.folder
        info.cell.move(to: page, animated: false)
        delegate?.homeAppsManagerDidUpdateItems(self)
    }
    
    func homeAppsFolderViewControllerDismissAnimationDidFinish(_ controller: HomeAppsFolderViewController) {
        guard let info = openFolderInfo else { return }
        viewController.dismiss(animated: false, completion: {
            self.openFolderInfo = nil
            if self.isEditing {
                info.cell.startShaking()
            }
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: {
            if self.isEditing {
                info.cell.moveToFirstAvailablePage()
            } else {
                info.cell.move(to: 0, animated: true)
            }
        })
        guard let folderIndex = items[currentPage].firstIndex(where: { $0 === info.folder }), let pageCell = currentPageCell else {
            return
        }
        if info.shouldCancelCreation {
            if let cell = pageCell.collectionView.cellForItem(at: IndexPath(item: folderIndex, section: 0)) as? AppFolderCell {
                cell.revokeFolderCreation {
                    self.items[self.currentPage][folderIndex] = info.folder.pages[0][0]
                    pageCell.items = self.items[self.currentPage]
                    pageCell.collectionView.performBatchUpdates({
                        pageCell.collectionView.reloadItems(at: [IndexPath(item: folderIndex, section: 0)])
                    }, completion: nil)
                }
            }
        } else if info.folder.pages.reduce(0, { $0 + $1.count }) == 0 {
            items[currentPage].remove(at: folderIndex)
            pageCell.delete(item: info.folder)
        }
    }
    
}
