import { Fragment, type ReactNode } from 'react'

type TextBlock =
  | { type: 'paragraph'; text: string }
  | { type: 'list'; items: string[][] }

function parseText(text: string): TextBlock[] {
  const blocks: TextBlock[] = []
  const lines = text.split(/\r?\n/)
  let listItems: string[][] = []

  const flushList = () => {
    if (listItems.length) {
      blocks.push({ type: 'list', items: listItems })
      listItems = []
    }
  }

  for (const rawLine of lines) {
    const line = rawLine.trimEnd()
    if (line.startsWith('- ')) {
      listItems.push([line.slice(2).trim()])
      continue
    }
    if (/^\s{2,}\S/.test(rawLine) && listItems.length) {
      listItems[listItems.length - 1].push(line.trim())
      continue
    }

    flushList()
    if (line.trim()) blocks.push({ type: 'paragraph', text: line.trim() })
  }

  flushList()
  return blocks
}

const inlinePattern = /(\*\*[^*]+\*\*|`[^`]+`)/g

function renderInline(text: string): ReactNode {
  return text.split(inlinePattern).map((part, index) => {
    if (part.startsWith('**') && part.endsWith('**')) {
      return <strong key={`${part}-${index}`}>{part.slice(2, -2)}</strong>
    }
    if (part.startsWith('`') && part.endsWith('`')) {
      return <code key={`${part}-${index}`}>{part.slice(1, -1)}</code>
    }
    return <Fragment key={`${part}-${index}`}>{part}</Fragment>
  })
}

function renderLines(lines: string[]): ReactNode {
  return lines.map((line, index) => (
    <Fragment key={`${line}-${index}`}>
      {index > 0 && <br />}
      {renderInline(line)}
    </Fragment>
  ))
}

export function ChatMessageText({ text }: { text: string }) {
  return (
    <div className="chat-message-text">
      {parseText(text).map((block, index) =>
        block.type === 'paragraph' ? (
          <p key={`${block.text}-${index}`}>{renderInline(block.text)}</p>
        ) : (
          <ul key={`list-${index}`}>
            {block.items.map((item, itemIndex) => (
              <li key={`${item[0]}-${itemIndex}`}>{renderLines(item)}</li>
            ))}
          </ul>
        ),
      )}
    </div>
  )
}
