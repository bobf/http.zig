const std = @import("std");
const httpz = @import("httpz");
const Allocator = std.mem.Allocator;

var index_file_contents: []u8 = undefined;

// Started in main.zig which starts 3 servers, on 3 different ports, to showcase
// small variations in using httpz.
pub fn start(allocator: Allocator) !void {
	var server = try httpz.Server().init(allocator, .{
		.workers = .{.max_conn = 200}
	});
	defer server.deinit();
	var router = server.router();

	server.notFound(notFound);

	var index_file = try std.fs.cwd().openFile("example/index.html", .{});
	defer index_file.close();
	index_file_contents = try index_file.readToEndAlloc(allocator, 100000);
	defer allocator.free(index_file_contents);

	router.get("/", index);
	router.get("/hello", hello);
	router.get("/json/hello/:name", json);
	router.get("/writer/hello/:name", writer);
	router.get("/static_file", staticFile);
	router.get("/cached_static_file", cachedStaticFile);
	try server.listen();
}

fn index(_: *httpz.Request, res: *httpz.Response) !void {
	res.body(
		\\<!DOCTYPE html>
		\\ <ul>
		\\ <li><a href="/hello?name=Teg">Querystring + text output</a>
		\\ <li><a href="/writer/hello/Ghanima">Path parameter + serialize json object</a>
		\\ <li><a href="/json/hello/Duncan">Path parameter + json writer</a>
		\\ <li><a href="/static_file">Static file</a>
		\\ <li><a href="/cached_static_file">Cached static file</a>
		\\ <li><a href="http://localhost:5883/increment">Global shared state</a>
	);
}

fn hello(req: *httpz.Request, res: *httpz.Response) !void {
	const query = try req.query();
	const name = query.get("name") orelse "stranger";

	// One solution is to use res.arena
	// var out = try std.fmt.allocPrint(res.arena, "Hello {s}", .{name});
	// try res.body(out);

	// another is to use res.writer(), which might be more efficient in some cases
	try std.fmt.format(res.writer(), "Hello {s}", .{name});
}

fn json(req: *httpz.Request, res: *httpz.Response) !void {
	const name = req.param("name").?;
	try res.json(.{ .hello = name }, .{});
}

fn writer(req: *httpz.Request, res: *httpz.Response) !void {
	res.content_type = httpz.ContentType.JSON;

	const name = req.param("name").?;
	var ws = std.json.writeStream(res.writer(), .{.whitespace = .indent_4});
	try ws.beginObject();
	try ws.objectField("name");
	try ws.write(name);
	try ws.endObject();
}

fn staticFile(_: *httpz.Request, res: *httpz.Response) !void {
	var index_file = try std.fs.cwd().openFile("example/index.html", .{});
	defer index_file.close();
	return res.body(try index_file.readToEndAlloc(res.arena, 100000));
}

fn cachedStaticFile(req: *httpz.Request, res: *httpz.Response) !void {
	_ = req;
	return res.body(index_file_contents);
}

fn notFound(_: *httpz.Request, res: *httpz.Response) !void {
	res.status = 404;
	res.body("Not found");
}
