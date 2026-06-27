import { createModalApp, destroyModalApp } from '@/utils/modalAppFactory'
import EditSheetModalComponent from './index.vue'

export interface EditSheetModalOptions {
  itemId: string | number
  editPageId: string | number
  onClose?: (result: boolean) => void
}

export default function EditSheetModal(options: EditSheetModalOptions): Promise<boolean> {
  return new Promise((resolve) => {
    const { app, mountNode } = createModalApp(EditSheetModalComponent, {
      itemId: options.itemId,
      editPageId: options.editPageId,
      onClose: (result: boolean) => {
        resolve(result)
        setTimeout(() => {
          destroyModalApp(app, mountNode)
        }, 300)
      }
    })
    app.mount(mountNode)
  })
}
