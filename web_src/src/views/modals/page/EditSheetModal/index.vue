<template>
  <EditorModal :show="true">
    <div class="edit-sheet-modal">
      <!-- 顶部工具栏（与MD编辑一致的风格） -->
      <div class="edit-header">
        <div class="header-left">
          <!-- 关闭按钮 -->
          <a-button class="close-btn" @click="handleClose">
            <i class="fas fa-times"></i>
          </a-button>

          <!-- 页面标题编辑 -->
          <template v-if="!isEditingTitle">
            <a-tooltip :title="$t('page.click_to_edit_page_title')">
              <span class="page-title" @click="isEditingTitle = true">
                {{ pageTitle || $t('page.untitled') }}
              </span>
            </a-tooltip>
          </template>
          <CommonInput
            v-else
            v-model="pageTitle"
            class="page-title-input"
            :placeholder="$t('page.input_page_title')"
            @blur="isEditingTitle = false"
            @keyup.enter="isEditingTitle = false"
          />

          <!-- 草稿标签 -->
          <a-tag v-if="isDraft" color="orange" class="draft-tag">{{ $t('page.draft') }}</a-tag>

          <!-- 目录选择 -->
          <a-tooltip :title="$t('page.select_catalog')">
            <span class="catalog-selector" @click="handleShowSelectCatalog">
              <i class="fas fa-folder-open"></i>
              {{ catalogName }}
            </span>
          </a-tooltip>
        </div>

        <div class="header-right">
          <!-- 主题切换 -->
          <a-tooltip
            :title="
              appStore.theme === 'light'
                ? $t('common.dark_mode')
                : $t('common.light_mode')
            "
            placement="bottom"
          >
            <div class="icon-item theme-toggle-item" @click="handleToggleTheme">
              <i class="fas fa-circle-half-stroke"></i>
            </div>
          </a-tooltip>

          <!-- 保存按钮（带下拉菜单） -->
          <MenuButton
            :text="$t('common.save')"
            :theme="'dark'"
            :list="saveMenuList"
            :spinning="saving"
            :left-icon="['fas', 'fa-save']"
            :on-click="handleSave"
          />
        </div>
      </div>

      <!-- 工具按钮组 -->
      <div class="fun-btn-group">
        <!-- 导出 -->
        <CommonButton
          :text="$t('item.export')"
          :left-icon="['fas', 'fa-arrow-down-to-bracket']"
          :theme="'light'"
          @click="handleExport"
        />

        <!-- 导入 -->
        <a-upload
          :show-upload-list="false"
          :before-upload="handleImport"
          accept=".xlsx,.xls"
        >
          <CommonButton
            :text="$t('item.import')"
            :left-icon="['fas', 'fa-arrow-up-from-bracket']"
            :theme="'light'"
          />
        </a-upload>

        <!-- 插入模板 -->
        <CommonButton
          :text="$t('page.insert_template')"
          :left-icon="['fas', 'fa-plug']"
          :theme="'light'"
          @click="handleOpenTemplateList"
        />

        <!-- 附件 -->
        <a-badge
          :count="attachmentCount"
          :offset="[10, 10]"
          :color="'var(--icon-tag-color)'"
        >
          <CommonButton
            :text="$t('page.attachments')"
            :left-icon="['fas', 'fa-paperclip']"
            :theme="'light'"
            @click="handleShowAttachment"
          />
        </a-badge>

        <!-- 历史版本 -->
        <CommonButton
          :text="$t('page.page_history_version')"
          :left-icon="['fas', 'fa-history']"
          :theme="'light'"
          @click="handleShowHistory"
        />
      </div>

      <!-- 表格编辑器 -->
      <div class="edit-content">
        <div id="sheet-modal-editor" class="sheet-editor"></div>
      </div>
    </div>
  </EditorModal>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, onBeforeUnmount, nextTick } from 'vue'
import { useI18n } from 'vue-i18n'
import { message } from 'ant-design-vue'
import EditorModal from '@/components/EditorModal.vue'
import CommonButton from '@/components/CommonButton.vue'
import CommonInput from '@/components/CommonInput.vue'
import MenuButton from '@/components/MenuButton.vue'
import type { ContextmenuModalItemInterface } from '@/components/ContextmenuModal'
import request from '@/utils/request'
import { useAppStore } from '@/store/app'
import Message from '@/components/Message'
import AlertModal from '@/components/AlertModal'
import AttachmentListModal from '@/views/modals/page/AttachmentListModal/index'
import HistoryModal from '@/views/modals/page/HistoryModal/index'
import CatalogSelectModal from '@/views/modals/catalog/SelectCatalogModal/index'
import SaveTemplateModal from '@/views/modals/page/SaveTemplateModal/index'
import TemplateSelectModal from '@/views/modals/page/TemplateSelectModal/index'
import NotifyModal from '@/views/modals/page/NotifyModal/index'

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
const appStore = useAppStore()
const originalTheme = ref<'light' | 'dark'>(appStore.theme)
const pageTitle = ref('')
const formCatId = ref(0)
const catalogs = ref<any[]>([])
const spreadsheetObj = ref<any>(null)
const saving = ref(false)
const sheetIsLock = ref(0)
const sheetIntervalId = ref(0)
const isEditingTitle = ref(false)
const attachmentCount = ref(0)
const isDraft = ref(false)
const isLocked = ref(false)

// 表格编辑需要浅色主题
if (appStore.theme === 'dark') {
  appStore.setTheme('light')
}

// 目录名称
const catalogName = computed(() => {
  const cat = catalogs.value.find((c) => c.catId === formCatId.value)
  return cat ? cat.title : t('catalog.root_catalog')
})

// 保存菜单（与MD编辑一致）
const saveMenuList = computed<ContextmenuModalItemInterface[]>(() => {
  const menu: ContextmenuModalItemInterface[] = []

  if (isDraft.value) {
    // 当前是草稿，显示"保存并发布"
    menu.push({
      icon: ['fas', 'fa-paper-plane'],
      text: t('page.save_and_publish'),
      value: 'publish',
      tooltip: t('page.save_and_publish_tooltip'),
      onclick: () => handleSave(false, '', 0),
    })
  } else {
    // 当前是发布状态，显示"保存为草稿"
    menu.push({
      icon: ['fas', 'fa-file-pen'],
      text: t('page.save_as_draft'),
      value: 'draft',
      tooltip: t('page.save_as_draft_tooltip'),
      onclick: () => handleSave(false, '', 1),
    })
  }

  menu.push(
    {
      icon: ['fas', 'fa-comment-dots'],
      text: t('page.save_and_notify'),
      value: 'notify',
      onclick: handleNotify,
    },
    {
      icon: ['fas', 'fa-file-export'],
      text: t('page.save_as_template'),
      value: 'template',
      onclick: handleSaveTemplate,
    },
    {
      icon: isLocked.value ? ['fas', 'fa-unlock'] : ['fas', 'fa-lock'],
      text: isLocked.value ? t('page.unlock') : t('page.lock_edit'),
      value: 'lock',
      onclick: handleToggleLock,
    }
  )

  return menu
})

// 主题切换
const handleToggleTheme = () => {
  appStore.toggleTheme()
}

// 锁定/解锁
const handleToggleLock = async () => {
  if (!props.editPageId) return
  try {
    const params: any = {
      page_id: String(props.editPageId),
      item_id: String(props.itemId),
    }
    if (isLocked.value) {
      params.lock_to = 1000
    }
    const res = await request('/api/page/setLock', params, 'post', false)
    if (res.error_code === 0) {
      isLocked.value = !isLocked.value
      Message.success(isLocked.value ? t('page.lock_success') : t('page.unlock_success'))
    }
  } catch (e) {
    console.error('锁定操作失败:', e)
  }
}

// 保存为模板
const handleSaveTemplate = async () => {
  if (!spreadsheetObj.value) return
  const content = JSON.stringify(spreadsheetObj.value.getData())
  await SaveTemplateModal({
    content,
    onSuccess: () => {
      Message.success(t('page.save_template_success'))
    },
  })
}

// 保存并通知
const handleNotify = async () => {
  await NotifyModal({
    itemId: props.itemId,
    pageId: props.editPageId,
    onConfirm: async (content: string) => {
      await handleSave(true, content)
    },
  })
}

// 从模板列表选择模板
const handleOpenTemplateList = async () => {
  await TemplateSelectModal({
    itemId: Number(props.itemId),
    onInsert: (content: string) => {
      if (!spreadsheetObj.value) return
      // 尝试解析为sheet数据
      try {
        const sheetData = JSON.parse(content)
        if (Array.isArray(sheetData)) {
          // 是sheet格式，获取当前数据，用模板覆盖当前active sheet
          const currentData = spreadsheetObj.value.getData()
          if (sheetData.length > 0 && currentData.length > 0) {
            // 替换当前active sheet
            const activeIndex = spreadsheetObj.value.activeSheetIndex || 0
            currentData[activeIndex] = sheetData[0]
            spreadsheetObj.value.loadData(currentData)
            Message.success(t('page.insert_template_success'))
          } else {
            // 没有当前sheet，直接加载
            spreadsheetObj.value.loadData(sheetData)
            Message.success(t('page.insert_template_success'))
          }
        } else {
          // 不是sheet格式
          Message.warning(t('page.template_not_sheet'))
        }
      } catch (e) {
        // 内容不是JSON，不适用于sheet
        Message.warning(t('page.template_not_sheet'))
      }
    },
  })
}

// 加载目录列表
const loadCatalogs = async () => {
  if (!props.itemId) return
  try {
    const data = await request('/api/catalog/catListName', {
      item_id: String(props.itemId),
    }, 'post', false)
    if (data.error_code === 0 && data.data) {
      catalogs.value = [
        { catId: 0, title: t('catalog.root_catalog') },
        ...(data.data || []).map((cat: any) => ({
          catId: Number(cat.cat_id),
          title: cat.cat_name,
        })),
      ]
    }
  } catch (e) {
    console.error('获取目录列表失败:', e)
  }
}

// 目录选择
const handleShowSelectCatalog = async () => {
  const newCatId = await CatalogSelectModal({
    itemId: props.itemId,
    catId: formCatId.value,
  })
  if (newCatId > 0) {
    formCatId.value = newCatId
    await loadCatalogs()
  }
}

// 附件
const handleShowAttachment = async () => {
  if (!props.editPageId) {
    await AlertModal(t('page.please_save_page_first'))
    return
  }
  await AttachmentListModal({
    itemId: props.itemId,
    pageId: props.editPageId,
    manage: true,
    onClose: () => {
      fetchAttachmentCount()
    },
  })
}

const fetchAttachmentCount = async () => {
  if (!props.editPageId) return
  try {
    const data = await request('/api/page/info', {
      page_id: String(props.editPageId),
    }, 'post', false)
    if (data.error_code === 0 && data.data) {
      attachmentCount.value = data.data.attachment_count > 0 ? data.data.attachment_count : 0
    }
  } catch (e) {
    // ignore
  }
}

// 历史版本
const handleShowHistory = async () => {
  if (!props.editPageId) {
    await AlertModal(t('page.please_save_page_first'))
    return
  }
  await HistoryModal({
    pageId: props.editPageId,
    onRestore: async (pageContent: string) => {
      let sheetData: any = {}
      try {
        const decoded = pageContent
          .replace(/&amp;/g, '&')
          .replace(/&lt;/g, '<')
          .replace(/&gt;/g, '>')
          .replace(/&quot;/g, '"')
          .replace(/&#039;/g, "'")
          .replace(/&apos;/g, "'")
        sheetData = JSON.parse(decoded)
      } catch (e) {
        console.error('解析历史版本数据失败:', e)
      }
      if (spreadsheetObj.value) {
        spreadsheetObj.value.loadData(sheetData)
      }
      Message.success(t('page.restore_success'))
    },
  })
}

// 加载页面内容
const loadPage = async () => {
  try {
    const res = await request('/api/page/info', {
      page_id: props.editPageId
    })
    if (res.error_code === 0 && res.data) {
      pageTitle.value = res.data.page_title || ''
      formCatId.value = Number(res.data.cat_id || 0)
      attachmentCount.value = res.data.attachment_count > 0 ? res.data.attachment_count : 0
      isLocked.value = res.data.is_locked === 1
      isDraft.value = res.data.is_draft === 1
      const rawContent = res.data.page_content || ''

      // 解析表格数据
      let sheetData: any = {}
      if (rawContent) {
        try {
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
const handleSave = async (notify = false, notifyContent = '', isDraftParam = -1) => {
  if (!spreadsheetObj.value) return
  saving.value = true

  // 如果标题为空，使用默认标题
  if (!pageTitle.value.trim()) {
    isEditingTitle.value = false
    pageTitle.value = t('page.untitled')
  }

  try {
    const requestData: Record<string, any> = {
      page_id: props.editPageId,
      page_title: pageTitle.value,
      item_id: props.itemId,
      cat_id: formCatId.value,
      is_urlencode: 1,
      page_content: encodeURIComponent(
        JSON.stringify(spreadsheetObj.value.getData())
      ),
      ext_info: JSON.stringify({ page_type: 'sheet' }),
      is_notify: notify ? 1 : 0,
      notify_content: notifyContent,
    }

    // 如果指定了草稿状态
    if (isDraftParam >= 0) {
      requestData.is_draft = isDraftParam
      isDraft.value = isDraftParam === 1
    }

    await request('/api/page/save', requestData)
    Message.success(t('page.save_success'))
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
      const aoa: any[][] = [[]]
      const rowobj = xws.rows
      for (let ri = 0; ri < rowobj.len; ++ri) {
        const row = rowobj[ri]
        if (!row) continue
        aoa[ri] = []
        Object.keys(row.cells).forEach((k) => {
          const idx = +k
          if (isNaN(idx)) return
          aoa[ri][idx] = row.cells[k].text
        })
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

// 导入（追加sheet到现有数据中）
const handleImport = (file: File) => {
  const reader = new FileReader()
  reader.onload = (e) => {
    const data = new Uint8Array(e.target?.result as ArrayBuffer)
    const workbook = XLSX.read(data, { type: 'array' })

    const stox = (wb: any) => {
      const out: any[] = []
      wb.SheetNames.forEach((name: string) => {
        const ws = wb.Sheets[name]
        const aoa = XLSX.utils.sheet_to_json(ws, { raw: false, header: 1 })
        const rows: any = {}
        aoa.forEach((r: any, i: number) => {
          const cells: any = {}
          ;(r as any[]).forEach((c: any, j: number) => {
            cells[j] = { text: c }
          })
          rows[i] = { cells }
        })
        out.push({ name, rows })
      })
      return out
    }

    if (spreadsheetObj.value) {
      const currentData = spreadsheetObj.value.getData()
      const importedSheets = stox(workbook)
      const mergedData = [...currentData, ...importedSheets]
      spreadsheetObj.value.loadData(mergedData)
      Message.success(t('page.import_success'))
    }
  }
  reader.readAsArrayBuffer(file)
  return false
}

// 关闭
const handleClose = async () => {
  if (spreadsheetObj.value) {
    try {
      spreadsheetObj.value.destroy()
    } catch (e) {
      // ignore
    }
    spreadsheetObj.value = null
  }

  clearInterval(sheetIntervalId.value)
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

onMounted(async () => {
  window.addEventListener('beforeunload', unlockOnClose)
  window.addEventListener('keydown', handleKeydown)
  await loadCatalogs()
  await loadPage()
  await fetchAttachmentCount()
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
  justify-content: space-between;
  align-items: center;
  padding: 16px 24px;
  background-color: var(--color-bg-primary);
  border-bottom: 1px solid var(--color-border);
  position: sticky;
  top: 0;
  z-index: 100;
}

.header-left {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: nowrap;
}

.header-right {
  display: flex;
  align-items: center;
  gap: 10px;

  .icon-item {
    width: 40px;
    height: 40px;
    display: flex;
    align-items: center;
    justify-content: center;
    background-color: var(--color-bg-secondary);
    border-radius: 8px;
    box-shadow: var(--shadow-xs);
    cursor: pointer;
    transition: all 0.15s ease;

    &:hover {
      background-color: var(--hover-overlay);
      box-shadow: var(--shadow-sm);
    }

    i {
      color: var(--color-text-primary);
      font-size: 16px;
    }
  }

  .theme-toggle-item i {
    color: var(--color-orange);
  }
}

.close-btn {
  width: 40px;
  height: 40px;
  padding: 0;
  border-radius: 8px;
  font-size: 16px;
  color: var(--color-text-primary);
  border: 1px solid var(--color-border);
  background: var(--color-bg-primary);
  box-shadow: var(--shadow-xs);
  transition: all 0.15s ease;

  &:hover {
    background: var(--hover-overlay);
    box-shadow: var(--shadow-sm);
    color: var(--color-text-primary);
    border-color: var(--color-border);
  }
}

.page-title {
  margin: 0 8px;
  font-size: 16px;
  font-weight: 500;
  color: var(--color-text-primary);
  cursor: pointer;
  padding: 8px 12px;
  border-radius: 6px;
  transition: all 0.15s ease;

  &:hover {
    background: var(--hover-overlay);
  }
}

.page-title-input {
  margin: 0 8px;
  min-width: 200px;
  max-width: 30vw;
}

.draft-tag {
  margin-left: 4px;
  font-size: 12px;
}

.catalog-selector {
  display: inline-flex;
  align-items: center;
  padding: 8px 12px;
  background-color: var(--color-bg-secondary);
  border: 1px solid var(--color-border);
  border-radius: 6px;
  box-shadow: var(--shadow-xs);
  cursor: pointer;
  font-size: 14px;
  color: var(--color-text-secondary);
  transition: all 0.15s ease;
  max-width: 300px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;

  i {
    margin-right: 6px;
    font-size: 14px;
  }

  &:hover {
    background-color: var(--hover-overlay);
    border-color: var(--color-active);
    color: var(--color-text-primary);
    box-shadow: var(--shadow-sm);
  }
}

.fun-btn-group {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 12px 24px;
  background-color: var(--color-bg-primary);
  border-bottom: 1px solid var(--color-border);

  .ant-btn {
    display: inline-flex;
    align-items: center;
    gap: 6px;

    i {
      margin-right: 4px;
    }
  }

  .ant-dropdown-trigger {
    display: inline-flex;
    align-items: center;
  }
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

// 响应式
@media (max-width: 1200px) {
  .edit-header {
    flex-direction: column;
    gap: 12px;
    padding: 12px 16px;
  }

  .header-left,
  .header-right {
    width: 100%;
    justify-content: center;
    flex-wrap: wrap;
  }

  .fun-btn-group {
    flex-wrap: wrap;
    padding: 12px 16px;
  }
}
</style>
