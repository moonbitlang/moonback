///|
async test "buffered request body preserves bytes across text and JSON reads" {
  let content = @utf8.encode("{\"message\":\"你好，MoonBack\"}")
  let reader = @io.MemoryReader(writer => writer.write(content))
  defer reader.close()
  @async.with_task_group(group => {
    let body = RequestBody::from_ready_stream(reader, group~)
    @test.assert_eq(body.binary(), content)
    @test.assert_eq(body.text(), @utf8.decode(content))
    @test.assert_eq(body.json(), { "message": "你好，MoonBack" })
    @test.assert_eq(body.binary(), content)
  })
}

///|
async test "binary request body preserves invalid UTF-8" {
  let content = b"\x00\xff\x80"
  let reader = @io.MemoryReader(writer => writer.write(content))
  defer reader.close()
  @async.with_task_group(group => {
    let body = RequestBody::from_ready_stream(reader, group~)
    @test.assert_eq(body.binary(), content)
    try body.text() catch {
      @utf8.Malformed(_) => ()
      err => raise err
    } noraise {
      _ => fail("expected malformed UTF-8")
    }
    @test.assert_eq(body.binary(), content)
  })
}

///|
async test "request body reader streams binary data without buffering" {
  let content = b"hello\x00\xff"
  let source = @io.MemoryReader(writer => writer.write(content))
  defer source.close()
  @async.with_task_group(group => {
    let body = RequestBody::from_ready_stream(source, group~)
    let reader = body.reader()
    @test.assert_eq(reader.read_exactly(2), b"he")
    @test.assert_eq(reader.read_all(), b"llo\x00\xff")
  })
}
