import React, { useState, useEffect, useRef } from 'react'
import { render, Box, Text, useInput } from 'ink'

let globalRenderCount = 0

function StaticComponent() {
  const renderCount = useRef(0)
  renderCount.current++
  
  useEffect(() => {
    console.error(`[StaticComponent] Render #${renderCount.current}`)
  })
  
  return (
    <Box borderStyle="round" padding={1}>
      <Text>Static Component - Renders: {renderCount.current}</Text>
    </Box>
  )
}

function DynamicComponent({ data }: { data: string }) {
  const renderCount = useRef(0)
  renderCount.current++
  globalRenderCount++
  
  useEffect(() => {
    console.error(`[DynamicComponent] Render #${renderCount.current}, Global: ${globalRenderCount}, Data: ${data}`)
  })
  
  return (
    <Box borderStyle="round" padding={1}>
      <Text>Dynamic Component - Renders: {renderCount.current}</Text>
      <Text>Data: {data}</Text>
    </Box>
  )
}

function App() {
  const [counter, setCounter] = useState(0)
  const [data, setData] = useState('initial')
  
  useInput((input) => {
    if (input === 'c') {
      setCounter(c => c + 1)
    }
    if (input === 'd') {
      setData(`updated-${Date.now()}`)
    }
    if (input === 'q') {
      process.exit(0)
    }
  })
  
  return (
    <Box flexDirection="column">
      <Text>Press 'c' to increment counter, 'd' to update data, 'q' to quit</Text>
      <Text>Counter: {counter}</Text>
      <StaticComponent />
      <DynamicComponent data={data} />
    </Box>
  )
}

render(<App />)
