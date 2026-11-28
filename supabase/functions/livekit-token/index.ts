// VERA CLOUD — secure LiveKit access-token endpoint
// Deploy as Supabase Edge Function: livekit-token
import { createClient } from "npm:@supabase/supabase-js@2";
import { AccessToken } from "npm:livekit-server-sdk";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const authorization = req.headers.get("Authorization") || "";
    if (!authorization.startsWith("Bearer ")) return json({ error: "يجب تسجيل الدخول أولاً." }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const livekitUrl = Deno.env.get("LIVEKIT_URL");
    const livekitApiKey = Deno.env.get("LIVEKIT_API_KEY");
    const livekitApiSecret = Deno.env.get("LIVEKIT_API_SECRET");
    if (!supabaseUrl || !anonKey || !livekitUrl || !livekitApiKey || !livekitApiSecret) {
      return json({ error: "إعدادات خدمة البث غير مكتملة على الخادم." }, 500);
    }

    const supabase = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: authData, error: authError } = await supabase.auth.getUser();
    const authUser = authData?.user;
    if (authError || !authUser) return json({ error: "جلسة الدخول غير صالحة. سجّل الدخول مجدداً." }, 401);

    const body = await req.json().catch(() => ({}));
    const sessionId = String(body?.session_id || "");
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(sessionId)) {
      return json({ error: "معرّف المحاضرة غير صالح." }, 400);
    }

    const [{ data: profile, error: profileError }, { data: allowed, error: accessError }, { data: liveClass, error: classError }] = await Promise.all([
      supabase.from("profiles").select("id,full_name,role,is_active").eq("id", authUser.id).maybeSingle(),
      supabase.rpc("can_access_live_class", { p_session_id: sessionId }),
      supabase.from("live_classes").select("id,status").eq("id", sessionId).maybeSingle(),
    ]);

    if (profileError) return json({ error: "تعذر التحقق من صلاحية الحساب." }, 403);
    if (!profile || profile.is_active !== true) return json({ error: "الحساب غير نشط أو غير مسجل." }, 403);
    if (accessError || allowed !== true || classError || !liveClass) {
      return json({ error: "ليس لديك صلاحية دخول هذه المحاضرة." }, 403);
    }
    if (liveClass.status === "ended" || liveClass.status === "cancelled") {
      return json({ error: "هذه المحاضرة منتهية أو ملغاة." }, 409);
    }

    const canPublish = profile.role === "admin" || profile.role === "teacher";
    const roomName = `vera-live-${sessionId}`;
    const token = new AccessToken(livekitApiKey, livekitApiSecret, {
      identity: authUser.id,
      name: profile.full_name || "مشارك",
      ttl: "2h",
    });
    token.addGrant({
      roomJoin: true,
      room: roomName,
      canSubscribe: true,
      canPublish,
      canPublishData: canPublish,
    });

    return json({
      server_url: livekitUrl,
      participant_token: await token.toJwt(),
      room_name: roomName,
      role: profile.role,
      can_publish: canPublish,
    });
  } catch (error) {
    console.error("livekit-token error:", error);
    return json({ error: "تعذر تجهيز اتصال المحاضرة. حاول مرة أخرى." }, 500);
  }
});
