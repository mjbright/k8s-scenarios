
curl -L -H "Host: quiz-g15.mjbright.click" --key certs/quiz.key --cert certs/quiz.crt 127.0.0.1:31923
curl -L -H "Host: quiz-g15.mjbright.click" --key certs/quiz.key --cert certs/quiz.crt https://127.0.0.1:31923
curl -kvL -H "Host: quiz-g15.mjbright.click" --key certs/quiz.key --cert certs/quiz.crt https://127.0.0.1:31923

curl -kvL --resolve quiz-g15.mjbright.click -H "Host: quiz-g15.mjbright.click" --key certs/quiz.key --cert certs/quiz.crt https://127.0.0.1:31923
curl -kvL --resolve quiz-g15.mjbright.click:443:127.0.0.1 -H "Host: quiz-g15.mjbright.click" --key certs/quiz.key --cert certs/quiz.crt https://127.0.0.1:31923
curl -vL --resolve quiz-g15.mjbright.click:443:127.0.0.1 -H "Host: quiz-g15.mjbright.click" --key certs/quiz.key --cert certs/quiz.crt https://127.0.0.1:31923
curl -kvL --resolve quiz-g15.mjbright.click:443:127.0.0.1 -H "Host: quiz-g15.mjbright.click" --key certs/quiz.key --cert certs/quiz.crt https://127.0.0.1:31923
curl -kvL --resolve quiz-g15.mjbright.click:31923:127.0.0.1 -H "Host: quiz-g15.mjbright.click" --key certs/quiz.key --cert certs/quiz.crt https://127.0.0.1:31923
