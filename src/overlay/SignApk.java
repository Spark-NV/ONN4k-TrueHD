import com.android.apksig.ApkSigner;
import java.io.File;
import java.io.FileInputStream;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.cert.X509Certificate;
import java.util.List;

/** Small apksig wrapper: signs an APK (v2 + v3) with a key from a PKCS12 keystore. */
public class SignApk {
    public static void main(String[] a) throws Exception {
        if (a.length != 5) {
            System.err.println("usage: SignApk <in.apk> <out.apk> <keystore.p12> <password> <alias>");
            System.exit(2);
        }
        KeyStore ks = KeyStore.getInstance("PKCS12");
        try (FileInputStream in = new FileInputStream(a[2])) {
            ks.load(in, a[3].toCharArray());
        }
        PrivateKey key = (PrivateKey) ks.getKey(a[4], a[3].toCharArray());
        X509Certificate cert = (X509Certificate) ks.getCertificate(a[4]);
        ApkSigner.SignerConfig signer =
                new ApkSigner.SignerConfig.Builder("overlay", key, List.of(cert)).build();
        new ApkSigner.Builder(List.of(signer))
                .setInputApk(new File(a[0]))
                .setOutputApk(new File(a[1]))
                .setMinSdkVersion(34)
                .setV1SigningEnabled(false)
                .setV2SigningEnabled(true)
                .setV3SigningEnabled(true)
                .build()
                .sign();
    }
}
