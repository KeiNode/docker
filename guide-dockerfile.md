1) Ringkasan instruksi Dockerfile yang sering dipakai (dan artinya singkat)

FROM <image> → base image. Wajib di tiap Dockerfile (boleh multi-stage).

ARG <name> → build-time variable (nilai bisa diberi saat docker build --build-arg).

ENV KEY=value → environment variable yang diset di container runtime.

WORKDIR /path → pindah/atur working directory.

COPY src dest → salin file dari context (folder build) ke image.

ADD src dest → mirip COPY, tapi bisa ekstrak tar & URL (biasanya gunakan COPY).

RUN <command> → jalankan perintah saat build (mis. instalasi).

CMD ["executable","param"] → default command saat container dijalankan (bisa di-override oleh docker run).

ENTRYPOINT ["executable","param"] → menetapkan program utama container; kombinasikan dengan CMD untuk arg default.

EXPOSE <port> → dokumentasi bahwa container mendengarkan port (tidak mem-publish otomatis).

VOLUME ["/data"] → deklarasi mount point untuk persistent storage.

USER <user> → jalankan perintah selanjutnya dengan user tertentu.

HEALTHCHECK --interval=... CMD <test> → cara Docker cek health container.

LABEL key="value" → metadata untuk image.

SHELL ["bash","-c"] → ubah shell default untuk RUN.
