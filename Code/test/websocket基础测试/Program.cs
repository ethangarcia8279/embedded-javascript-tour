using System;
using System.Collections.Generic;
using Weave.Base;

namespace ConsoleApp1
{
    class Program
    {
        static Weave.TCPClient.P2Pclient pclient = new Weave.TCPClient.P2Pclient(Weave.TCPClient.DataType.custom);
        static void Main(string[] args)
        {
            
            pclient.IsSSL = true;
            pclient.cert = new System.Security.Cryptography.X509Certificates.X509Certificate2("server.cer");
            pclient.ReceiveServerEventbit += Pclient_ReceiveServerEventbit;

            pclient.Start("127.0.0.1",9903);
            pclient.Send(new byte[] { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 });
        }

        private static void Pclient_ReceiveServerEventbit(byte command, byte[] data)
        {
            pclient.Send(new byte[] { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 });
        }
        public byte[] pack(string ContextXML)
        {
            QXT625 qXT625 = new QXT625();
            qXT625.ContextXML = ContextXML;
            return new byte[0];
        }
        public QXT625 unpack(byte[] ContextXML)
        {
            QXT625 qXT625 = new QXT625();
            
            return qXT625;
        }
        
    }
    public class QXT625
    {
        public int len;
        public string sName;
        public string rName;
        public string TYPE;

        public String verifydata;
        public byte AES = 2;
        public byte verifyMD5 = 1;
        public string ContextXML;
    }
     
}
