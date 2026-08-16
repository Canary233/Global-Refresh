import java.lang.reflect.Method;

public final class SceneRate {
    private static final int REQUEST_SCENE_REFRESH_RATE = 16777208;
    private static final String PRIVATE_DESCRIPTOR = "android.view.android.hardware.display.IDisplayManager";

    public static void main(String[] args) throws Exception {
        if (args.length >= 1 && "--labels".equals(args[0])) {
            printApplicationLabels(args);
            return;
        }
        if (args.length != 2) {
            throw new IllegalArgumentException("usage: SceneRate <package> <refresh-rate> | SceneRate --labels <package>...");
        }
        requestSceneRefreshRate(args[0], args[1]);
    }

    private static void requestSceneRefreshRate(String packageName, String refreshRate) throws Exception {
        Class<?> serviceManager = Class.forName("android.os.ServiceManager");
        Class<?> parcelClass = Class.forName("android.os.Parcel");
        Class<?> binderClass = Class.forName("android.os.IBinder");
        Method getService = serviceManager.getMethod("getService", String.class);
        Method obtain = parcelClass.getMethod("obtain");
        Method recycle = parcelClass.getMethod("recycle");
        Method writeInterfaceToken = parcelClass.getMethod("writeInterfaceToken", String.class);
        Method writeString = parcelClass.getMethod("writeString", String.class);
        Method writeInt = parcelClass.getMethod("writeInt", int.class);
        Method readException = parcelClass.getMethod("readException");
        Method transact = binderClass.getMethod("transact", int.class, parcelClass, parcelClass, int.class);

        Object display = getService.invoke(null, "display");
        if (display == null) {
            throw new IllegalStateException("display service unavailable");
        }

        Object data = obtain.invoke(null);
        Object reply = obtain.invoke(null);
        try {
            writeInterfaceToken.invoke(data, PRIVATE_DESCRIPTOR);
            writeString.invoke(data, packageName);
            writeInt.invoke(data, Integer.parseInt(refreshRate));
            Boolean handled = (Boolean) transact.invoke(display, REQUEST_SCENE_REFRESH_RATE, data, reply, 0);
            if (!handled.booleanValue()) {
                throw new IllegalStateException("private display request was not handled");
            }
            readException.invoke(reply);
        } finally {
            recycle.invoke(reply);
            recycle.invoke(data);
        }
    }

    private static void printApplicationLabels(String[] args) {
        Object packageManager = null;
        try {
            Method prepareLooper = Class.forName("android.os.Looper").getMethod("prepare");
            prepareLooper.invoke(null);
            Class<?> activityThread = Class.forName("android.app.ActivityThread");
            Method systemMain = activityThread.getDeclaredMethod("systemMain");
            systemMain.setAccessible(true);
            Object thread = systemMain.invoke(null);
            Method getSystemContext = activityThread.getDeclaredMethod("getSystemContext");
            getSystemContext.setAccessible(true);
            Object context = getSystemContext.invoke(thread);
            Method getPackageManager = Class.forName("android.content.Context").getMethod("getPackageManager");
            packageManager = getPackageManager.invoke(context);
        } catch (Exception ignored) {
            // A package name is still displayed when a vendor ROM blocks this hidden API.
        }

        for (int index = 1; index < args.length; index++) {
            String packageName = args[index];
            String label = packageName;
            if (packageManager != null) {
                try {
                    Class<?> packageManagerClass = Class.forName("android.content.pm.PackageManager");
                    Class<?> applicationInfoClass = Class.forName("android.content.pm.ApplicationInfo");
                    Method getApplicationInfo = packageManagerClass.getMethod("getApplicationInfo", String.class, int.class);
                    Method getApplicationLabel = packageManagerClass.getMethod("getApplicationLabel", applicationInfoClass);
                    Object applicationInfo = getApplicationInfo.invoke(packageManager, packageName, 0);
                    Object applicationLabel = getApplicationLabel.invoke(packageManager, applicationInfo);
                    if (applicationLabel != null && applicationLabel.toString().length() > 0) {
                        label = applicationLabel.toString();
                    }
                } catch (Exception ignored) {
                    // Removed or malformed packages are represented by their stable package name.
                }
            }
            System.out.println(packageName + "\t" + normalizeLabel(label));
        }
    }

    private static String normalizeLabel(String label) {
        return label.replace('\t', ' ').replace('\n', ' ').replace('\r', ' ').trim();
    }
}
