<template>
  <EditorModal :show="true">
    <div class="edit-sheet-modal">
      <!-- 顶部工具栏 -->
      <div class="edit-header">
        <div class="header-left">
          <a-button type="text" @click="handleClose">
            <i class="far fa-xmark"></i>
          </a-button>
          <span class="page-title">{{ pageTitle }}</span>
        </div>
        <div class="header-right">
          <a-button type="primary" @click="handleSave" :loading="saving">
            {{ $t('common.save') }}
          </a-button>
        </div>
      </div>

      <!-- 表格操作栏 -->
      <div class="sheet-toolbar">
        <a-button size="small" @click="handleExport">
          <i class="far fa-arrow-down-to-bracket"></i>
          {{ $t('item.export') }}
        </a-button>
        <a-upload
          :show-upload-list="false"
          :before-upload="handleImport"
          accept=".xlsx,.xls"
        >
          <a-button size="small">
            <i class="far fa-arrow-up-from-bracket"></i>
            {{ $t('item.import') }}
          </a-button>
        </a-upload>
      </div>

      <!-- 表格编辑器 -->
      <div class="edit-content">
        <div id="sheet-modal-editor" class="sheet-editor"></div>
      </div>
    </div>
  </EditorModal>
</template>

<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount, nextTick } from 'vue'
import { useI18n } from 'vue-i18n'
import { message } from 'ant-design-vue'
import EditorModal from '@/components/EditorModal.vue'
import request from '@/utils/request'
import { useAppStore } from '@/store/app'

declare const x_spreadsheet: any
declare const XLSX: any

interface Props {
  itemId: string | number
  editPageId: string | number
  onClose: (result: boolean) => void
}

const props = withDefaults(defineProps<Props>(), {
  itemId: 0,
  editPageId: 0,
  onClose: () => {}
})

const { t } = useI18n()
const pageTitle = ref('')
const spreadsheetObj = ref<any>(null)
const saving = ref(false)
const sheetIsLock = ref(0)
const sheetIntervalId = ref(0)
const appStore = useAppStore()
const originalTheme = ref<'light' | 'dark'>(appStore.theme)

// 保存原始主题，表格编辑需要浅色主题
if (appStore.theme === 'dark') {
  appStore.setTheme('light')
}

// 加载页面内容
const loadPage = async () => {
  try {
    const res = await request('/api/page/info', {
      page_id: props.editPageId
    })
    if (res.error_code === 0 && res.data) {
      pageTitle.value = res.data.page_title || ''
      const rawContent = res.data.page_content || ''

      // 解析表格数据
      let sheetData: any = {}
      if (rawContent) {
        try {
          // 解码 HTML 实体
          const decoded = rawContent
            .replace(/&amp;/g, '&')
            .replace(/&lt;/g, '<')
            .replace(/&gt;/g, '>')
            .replace(/&quot;/g, '"')
            .replace(/&#039;/g, "'")
            .replace(/&apos;/g, "'")
          sheetData = JSON.parse(decoded)
        } catch (e) {
          console.error('解析表格数据失败:', e)
        }
      }

      // 设置编辑锁
      await setLock()

      // 初始化表格编辑器
      await nextTick()
      initEditor(sheetData)
    }
  } catch (error) {
    console.error('加载表格页面失败:', error)
  }
}

// 初始化表格编辑器
const initEditor = (data: any) => {
  try {
    if (typeof window.x_spreadsheet === 'undefined') {
      message.error(t('item.sheet_load_failed'))
      return
    }

    const container = document.getElementById('sheet-modal-editor')
    if (!container) {
      console.error('表格容器未找到')
      return
    }

    // 设置语言
    try {
      if (typeof window.x_spreadsheet.locale === 'function') {
        const lang = localStorage.getItem('showdoc_language') || 'zh-cn'
        window.x_spreadsheet.locale(lang === 'en-US' ? 'en' : 'zh-cn')
      }
    } catch (e) {
      // ignore
    }

    spreadsheetObj.value = window.x_spreadsheet(container, {
      mode: 'edit',
      showToolbar: true,
      row: {
        len: 800,
        height: 25
      },
      view: {
        height: () => container.offsetHeight,
        width: () => container.offsetWidth
      }
    }).loadData(data)

    // 监听单元格编辑
    if (spreadsheetObj.value) {
      spreadsheetObj.value.on('cell-edited', () => {
        // 自动保存可以在这里实现
      })
    }
  } catch (e) {
    console.error('初始化表格编辑器失败:', e)
  }
}

// 设置编辑锁
const setLock = async () => {
  if (props.editPageId && props.itemId) {
    try {
      await request('/api/page/setLock', {
        page_id: props.editPageId,
        item_id: props.itemId
      })
      sheetIsLock.value = 1
      startHeartBeat()
    } catch (e) {
      console.error('设置编辑锁失败:', e)
    }
  }
}

// 解除编辑锁
const unlock = async () => {
  if (!sheetIsLock.value) return
  if (!props.editPageId || !props.itemId) return
  try {
    await request('/api/page/setLock', {
      page_id: props.editPageId,
      item_id: props.itemId,
      lock_to: 1000
    })
    sheetIsLock.value = 0
  } catch (e) {
    // ignore
  }
}

// 心跳保持锁定
const startHeartBeat = () => {
  sheetIntervalId.value = window.setInterval(() => {
    if (sheetIsLock.value && props.editPageId) {
      request('/api/page/setLock', {
        page_id: props.editPageId,
        item_id: props.itemId
      })
    }
  }, 3 * 60 * 1000)
}

// 保存
const handleSave = async () => {
  if (!spreadsheetObj.value) return
  saving.value = true

  try {
    await request('/api/page/save', {
      page_id: props.editPageId,
      page_title: pageTitle.value,
      item_id: props.itemId,
      is_urlencode: 1,
      page_content: encodeURIComponent(
        JSON.stringify(spreadsheetObj.value.getData())
      ),
      ext_info: JSON.stringify({ page_type: 'sheet' })
    })
    message.success(t('common.save_success'))
  } catch (error) {
    console.error('保存失败:', error)
    message.error(t('common.save_failed'))
  } finally {
    saving.value = false
  }
}

// 导出
const handleExport = () => {
  if (!spreadsheetObj.value) return

  const xtos = (sdata: any) => {
    const out = XLSX.utils.book_new()
    sdata.forEach((xws: any) => {
      const aoa: any[][] = []
      const rowobj = xws.rows
      for (let ri = 0; ri < rowobj.len; ++ri) {
        const row = rowobj[ri]
        if (!row) continue
        const cells: any[] = []
        for (let ci = 0; ci < row.len; ++ci) {
          const cell = row.cells[ci]
          if (!cell) {
            cells.push('')
            continue
          }
          let value = cell.text || ''
          if (cell.value !== undefined && cell.value !== null) {
            value = cell.value
          }
          cells.push(value)
        }
        aoa.push(cells)
      }
      const ws = XLSX.utils.aoa_to_sheet(aoa)
      XLSX.utils.book_append_sheet(out, ws, xws.name)
    })
    return out
  }

  try {
    const wb = xtos(spreadsheetObj.value.getData())
    XLSX.writeFile(wb, `${pageTitle.value || 'sheet'}.xlsx`)
  } catch (e) {
    console.error('导出失败:', e)
  }
}

// 导入
const handleImport = (file: File) => {
  const reader = new FileReader()
  reader.onload = (e) => {
    const data = new Uint8Array(e.target?.result as ArrayBuffer)
    const workbook = XLSX.read(data, { type: 'array' })

    const sto = (wb: any) => {
      const sheets: any[] = []
      wb.SheetNames.forEach((name: string) => {
        const ws = wb.Sheets[name]
        const range = XLSX.utils.decode_range(ws['!ref'] || 'A1')
        const rows: any = { len: range.e.r + 1 }
        for (let R = range.s.r; R <= range.e.r; ++R) {
          const cells: any = {}
          for (let C = range.s.c; C <= range.e.c; ++C) {
            const addr = XLSX.utils.encode_cell({ r: R, c: C })
            const cell = ws[addr]
            if (!cell) continue
            cells[C] = { text: String(cell.v || '') }
          }
          if (Object.keys(cells).length > 0) {
            rows[R] = { cells }
          }
        }
        sheets.push({ name, rows, cols: { len: range.e.c + 1 } })
      })
      return sheets
    }

    if (spreadsheetObj.value) {
      spreadsheetObj.value.loadData(sto(workbook))
    }
  }
  reader.readAsArrayBuffer(file)
  return false
}

// 关闭
const handleClose = async () => {
  // 销毁表格实例
  if (spreadsheetObj.value) {
    try {
      spreadsheetObj.value.destroy()
    } catch (e) {
      // ignore
    }
    spreadsheetObj.value = null
  }

  // 停止心跳
  clearInterval(sheetIntervalId.value)

  // 解锁
  await unlock()

  // 恢复主题
  if (originalTheme.value === 'dark') {
    appStore.setTheme('dark')
  }

  props.onClose(true)
}

// 关闭页面时解锁
const unlockOnClose = () => {
  if (sheetIsLock.value && props.editPageId && props.itemId) {
    const formData = new FormData()
    formData.append('page_id', String(props.editPageId))
    formData.append('item_id', String(props.itemId))
    formData.append('lock_to', '1000')
    navigator.sendBeacon('/server/?s=/api/page/setLock', formData)
  }
}

// Ctrl+S 快捷键保存
const handleKeydown = (e: KeyboardEvent) => {
  if ((e.ctrlKey || e.metaKey) && e.key === 's') {
    e.preventDefault()
    handleSave()
  }
}

onMounted(() => {
  window.addEventListener('beforeunload', unlockOnClose)
  window.addEventListener('keydown', handleKeydown)
  loadPage()
})

onBeforeUnmount(() => {
  window.removeEventListener('beforeunload', unlockOnClose)
  window.removeEventListener('keydown', handleKeydown)
  clearInterval(sheetIntervalId.value)
})
</script>

<style lang="scss" scoped>
.edit-sheet-modal {
  display: flex;
  flex-direction: column;
  height: 100%;
  background-color: var(--color-bg-primary);
}

.edit-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 8px 16px;
  border-bottom: 1px solid var(--color-border);
  flex-shrink: 0;

  .header-left {
    display: flex;
    align-items: center;
    gap: 12px;

    .page-title {
      font-size: 16px;
      font-weight: 500;
    }
  }

  .header-right {
    display: flex;
    align-items: center;
    gap: 8px;
  }
}

.sheet-toolbar {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 16px;
  border-bottom: 1px solid var(--color-border);
  flex-shrink: 0;
}

.edit-content {
  flex: 1;
  overflow: hidden;
  position: relative;
  padding: 0;

  .sheet-editor {
    width: 100%;
    height: 100%;
  }
}
</style>
