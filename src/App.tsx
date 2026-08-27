import { useEffect } from "react";
import { Routes, Route, useNavigate } from "react-router";
import { Toaster } from "@/components/ui/sonner";
import { useTheme } from "@/hooks/useTheme";
import DevicesPage, { LAST_DEVICE_KEY } from "./pages/DevicesPage";
import HomePage from "./pages/HomePage";
import ProjectPage from "./pages/ProjectPage";
import BrowsePage from "./pages/BrowsePage";
import ChatPage from "./pages/ChatPage";

// 记忆最后设备：下次启动直达该设备的会话界面
function Entry() {
  const navigate = useNavigate();
  useEffect(() => {
    const last = localStorage.getItem(LAST_DEVICE_KEY);
    navigate(last ? `/d/${last}` : "/devices", { replace: true });
  }, [navigate]);
  return null;
}

export default function App() {
  const { theme } = useTheme();
  return (
    <>
      <Routes>
        <Route path="/" element={<Entry />} />
        <Route path="/devices" element={<DevicesPage />} />
        <Route path="/d/:deviceId" element={<HomePage />} />
        <Route path="/d/:deviceId/project/:path" element={<ProjectPage />} />
        <Route path="/d/:deviceId/browse" element={<BrowsePage />} />
        <Route path="/chat/:sessionId" element={<ChatPage />} />
        <Route path="*" element={<Entry />} />
      </Routes>
      <Toaster
        position="top-center"
        offset={{ top: 72 }}
        mobileOffset={{ top: 72 }}
        expand
        theme={theme}
      />
    </>
  );
}
