// JSON-lines protocol between the Swift app and this process.
//
// stdin  (from app): {type:"say", text, seq} | {type:"messageTask", job, text} | {type:"stopTask", job}
//                    | {type:"interrupt"} | {type:"reset"} | {type:"continue", sessionId}
//                    | {type:"mcpSignIn", name}
//                    | {type:"forgetThread", sessionId}: the user deleted that thread (and its tasks)
// stdout (to app):   {type:"ready"} | {type:"tool", name, summary} | {type:"text", text}
//                    | {type:"result", text, isError, isInterrupted?, isDelegated?}
//                    | {type:"screen", reason} | {type:"log", msg}
//                    | {type:"idle", seq} | {type:"control", id, action}
//                    | {type:"mcpStatus", servers: [{name, status, error, source, tools}], problems: [{name, error}]}
//                    | {type:"task", job, name, status, sessionId}: a task started, was messaged, finished or stopped
//                    | {type:"skills", skills: [{name, description, argumentHint}]}: the skills Bol can use
//                    | {type:"mcpSignIn", name, url, error}: a server's sign-in page was opened (or couldn't be)
//                    | {type:"mcpSignInDone", name, status}: it connected, failed, or the sign-in timed out
// {type:"mcpStatus"} on stdin asks for one; it's also sent when servers connect or mcp.json changes.
// `control` asks the app to operate the Mac (see control.ts); it answers with
// {type:"controlResult", id, text, isError, images} on stdin, `images` being JPEG paths to attach.
// tool, text, result and screen carry `job` (the task id) when they come from a task.
// `isDelegated`: the thread's turn only handed the request to a task, so its reply is an acknowledgement.
// `idle` means the thread has nothing left to do (queued requests included); `seq` is the
// sequence number of the latest `say` it had received.

import { z } from 'zod'

export const Command = z.discriminatedUnion('type', [
	z.object({ type: z.literal('say'), text: z.string(), seq: z.number().optional() }),
	z.object({ type: z.literal('messageTask'), job: z.string(), text: z.string().min(1) }),
	z.object({ type: z.literal('stopTask'), job: z.string() }),
	z.object({ type: z.literal('interrupt') }),
	z.object({ type: z.literal('reset') }),
	z.object({ type: z.literal('continue'), sessionId: z.string().regex(/^[0-9a-f-]{36}$/) }),
	z.object({ type: z.literal('mcpStatus') }),
	z.object({ type: z.literal('mcpSignIn'), name: z.string().min(1) }),
	z.object({ type: z.literal('forgetThread'), sessionId: z.string().regex(/^[0-9a-f-]{36}$/) }),
	z.object({
		type: z.literal('controlResult'),
		id: z.string(),
		text: z.string(),
		isError: z.boolean(),
		images: z.array(z.string()),
	}),
])
export type Command = z.infer<typeof Command>

export function emit(obj: Record<string, unknown>) {
	process.stdout.write(JSON.stringify(obj) + '\n')
}

export function log({ msg }: { msg: string }) {
	emit({ type: 'log', msg })
}
