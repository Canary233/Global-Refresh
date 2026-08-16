import java.lang.reflect.Method;

public final class SceneRate {
    private static final int REQUEST_SCENE_REFRESH_RATE = 16777208;
    private static final String PRIVATE_DESCRIPTOR = "android.view.android.hardware.display.IDisplayManager";

    public static void main(String[] args) throws Exception {
        if (args.length != 2) {
            throw new IllegalArgumentException("usage: SceneRate <package> <refresh-rate>");
        }

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
            writeString.invoke(data, args[0]);
            writeInt.invoke(data, Integer.parseInt(args[1]));
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
}
